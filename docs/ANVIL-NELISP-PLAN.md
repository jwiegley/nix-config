# Anvil Fleet Backend Plan

Status: frozen on 2026-07-11, amended through 2026-07-15 after repeated production hangs and final adversarial cleanup review. This document fixes the objective and the evidence required for completion. It may be amended to record a stricter requirement or a newly discovered fact; it is not to be weakened to accommodate an implementation.

## Objective

> Right now in this repository we build anvil.el for use here on this macOS machine with the same Emacs that I use for coding and development. If you research the anvil.el project at https://github.com/zawatton/anvil.el, you'll see that it has a "NeLisp" approach for running on system that may not have Emacs. I want to use this feature for all of the Linux machines that this configuration is built on, so that I can make Anvil MCP available to all of my agents on all platforms. This also implies some changes to ~/src/promptdeploy so that the next time I deploy this MCP server will be made available everywhere that Anvil is running. $command-wiggum

The user subsequently made ARM64 Linux on Vulcan and AMD64 Linux on Andoria-08 explicit requirements, asked whether a full headless-Emacs backend could coexist safely on the shared-home Andoria family, and required one Linux Boolean to select either the NeLisp or headless-Emacs-daemon approach. The user then required an independent macOS Boolean selecting the current interactive development Emacs or a second dedicated headless Anvil Emacs, because agent traffic can intermittently lock the interactive Hera session.

The work therefore comprises one cross-repository contract: Nix supplies a reproducible launcher and the platform-specific backends; two independent Home Manager Booleans select the Linux and Darwin behavior; promptdeploy registers one stable launcher wherever the corresponding runtime is present; and the deployed Anvil skill describes the capabilities actually offered by each backend.

The user subsequently required full reliability rather than merely process isolation. A logical Codex or Claude MCP client must own its own supervised root Emacs, including internal agents that establish distinct MCP transports. A stuck request must produce a bounded error and an automatic clean replacement without making another client unavailable. The implementation may patch anvil.el itself, but it must not patch Codex or Claude.

## Authoritative baseline

The current worktrees and live consumers are authoritative. The following upstream sources were checked on 2026-07-11:

- anvil.el master/version 1.3.0 at `574568a95a2bd8fceca6c9cd3bec0f94ecf0e6a9`;
- NeLisp main at `7f501835d30270c428613a8fb314d59bbec01023`;
- NeLisp v0.5.1 at `f753209d53b372933b829345fe4373acad67bcb5`; and
- anvil.el v1.1.1 at `d50ce32b71c5fa46da3aa661481c8be44fee4f97`.

The current interactive and dedicated service release is pinned centrally by
`packages/anvil-mcp/source.nix` to John Wiegley's anvil.el commit
`39f9c59bfc51379db6243b1be20edca1ea783c2b`. That source includes the complete
issue-53 lifecycle and wire-protocol hardening, plus the final readiness,
staged-request cleanup, signal-custody, and bounded-I/O corrections; the former
local eleven-patch stack has been removed.

Current upstream documentation describes a Rust standalone path that has since been removed from NeLisp main. The later pure-Elisp launcher in anvil.el master does not match the current NeLisp executable path or command line, carries an unproved and materially smaller tool surface, and records a five-to-seven-minute cold load. The standalone branch therefore adopts the last reproducible released compatibility pair: NeLisp v0.5.1 with the byte-identical Anvil modules from anvil.el v1.1.1. This is a deliberate compatibility pin, not an assertion that current heads are interoperable.

The dedicated branch uses current pinned anvil.el 1.3.0 and the separately pinned anvil-ide package. Linux pairs them with a Nix-built Emacs 30 no-X package; Darwin reuses the pinned MacPort Emacs while running a separate minimal daemon. The live interactive Mac remains the compatibility baseline at 13 `anvil` eval/IDE tools plus 65 `emacs-eval` typed tools. The dedicated daemon loads the complete configured optional set `(ide elisp sexp semantic sqlite pdf cron state shell-filter context)`, yielding 76 direct typed tools. It publishes those typed tools into the main `anvil` registry as well, producing one 89-tool registration compatible with static promptdeploy configuration; the direct typed registry remains available for diagnosis and worker offload.

## Standing constraints

- Linux support covers native `aarch64-linux` on Vulcan and native `x86_64-linux` on Andoria-08.
- `johnw.anvil.useHeadlessEmacs` is the Linux selector. It defaults to `false`: false selects NeLisp; true selects the dedicated headless Emacs daemon.
- `johnw.anvil.useDedicatedDarwinEmacs` is the independent macOS selector. It defaults to `false`: false uses the existing interactive development Emacs; true uses a separate dedicated daemon.
- `johnw.anvil.usePerAgentDaemon` defaults to `true` in dedicated mode: each logical MCP bridge gets a supervised root daemon identified by that bridge process and the immutable packaged generation. Distinct Codex and Claude agents must not share a root failure domain. Setting it to `false` selects the single host daemon fallback.
- Agents register one unified `anvil` MCP transport. The dedicated daemon may retain its internal `emacs-eval` registry for implementation and direct diagnosis, but a second client registration must not silently share the same root or duplicate the failure domain.
- Supervisor status, leases, sockets, and state are generation-aware. An already-running bridge remains pinned to its original generation until that bridge exits; a newly executed launcher must never attach to a responsive daemon from an older package generation.
- Every request is at-most-once. Readiness probes may be retried before dispatch; a request that may have reached Emacs is never replayed. A wedged root is terminated within a documented finite deadline, its Anvil-owned guarded process group is reaped, and a subsequent request from the same still-running MCP bridge is served by a replacement root or receives a bounded structured error.
- Long-running asynchronous evaluation must execute outside the root Emacs event loop. It may not extend the synchronous root watchdog merely by marking a lease active. Direct or indirect attempts by a root-owned shell command to call the same root socket must fail immediately instead of deadlocking.
- Timeout ordering is a declared cross-client contract: the 45-second heartbeat is shorter than the 120-second cooperative synchronous budget, which is shorter than the 225-second root watchdog and 250-second bridge-dispatch cap. Runner READY/ACK control has a configured ten-second budget plus a conservative two-second Bash 3.2 whole-clock allowance; guarded runner identity discovery is capped at five seconds, and the parent handshake at ten seconds. Parsing, frame reads, and each emacsclient probe are capped at 20 seconds, while readiness and aggregate worker spawning are capped at 30 seconds. Each bounded runner may then spend one one-second private-status wait and two retirement drains of at most three seconds each; supervisor teardown uses separate bounded five-second waits. The 474-second inline and 513-second large-request envelopes remain below the 540-second client tool limit. Startup uses a separate 20-second initialize cap; its conservative 443-second cleaner, supervisor, parse/readiness, parent-guard, and retirement envelope also fits beneath the 540-second client startup limit. Runtime overrides may shorten but not enlarge these maxima; asynchronous evaluation retains its independent 600-second default. Promptdeploy must render 540-second startup and tool deadlines. Home Manager exports `MCP_TIMEOUT=540000` only as an inherited startup fallback, so GUI-launched Darwin clients still require the rendered per-server timeout.
- The NeLisp runtime closure contains no Emacs executable or Emacs package. The Linux headless closure deliberately contains `emacs30-nox` and current pinned anvil.el.
- Both Darwin branches reuse the Emacs package built by `overlays/10-emacs.nix`; the dedicated branch is a separate process with `-Q`, minimal Anvil initialization, and isolated state.
- Every actual Linux consumer imports `config/johnw.nix`; VPS deliberately omits `config/packages.nix`, while Vulcan and VPS omit the Emacs overlay. The shared Home Manager module is consequently the canonical installation point, and the headless package may not depend on importing the large Emacs overlay.
- Vulcan is configured by `/etc/nixos/flake.nix`. Andoria-08 and its siblings are configured by the shared `~/.config/home-manager/flake.nix`.
- Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server share the same NFS home and Home Manager profile. One identical unit must derive the actual short hostname at runtime; it must not trust the Andoria flake's hard-coded `hostname = "andoria-08"`.
- Headless sockets and mutable Emacs/Anvil state are host-local. The default per-agent socket is `$RUNTIME_ROOT/$SHORT_HOST/agents/$AGENT_KEY/emacs/server`; the shared-host fallback uses `$RUNTIME_ROOT/$SHORT_HOST/emacs/server`. Linux defaults `$RUNTIME_ROOT` to `/run/user/$UID/anvil`, while Darwin uses `/tmp/anvil-emacs-$UID`. Durable state is beneath `/var/tmp/anvil-emacs-$UID/$SHORT_HOST`, with distinct root and worker Emacs directories, schema caches, SQLite databases, and native-comp caches. Temporary root and worker trees live beneath the host-qualified runtime root; Linux prunes stale temporary trees only after acquiring daemon-lifetime locks on both the runtime and state directories. Every runtime/state component must be a real `0700` directory owned by the current user, and sockets may not be symlinks. No mutable daemon state or server file is placed on NFS.
- The standalone server is not permitted to pass by falling into upstream's one-tool `hello` placeholder registry. Exact tool-surface and behavioral checks are mandatory.
- promptdeploy stores only a PATH-stable launcher command. Nix store paths, user-specific home paths, Darwin socket paths, source downloads, and build steps remain outside MCP definitions.
- Deployment, Home Manager activation, NixOS switches, pushes, and shared-history rewrites require explicit user authorization. The 2026-07-15 release session has that authorization and must preserve unrelated worktrees while deploying the reviewed commits.
- No SOPS secret is read or decrypted.
- Commands run in the environment already supplied by the worktree and its direnv state. `nix develop` is not used.

## Implementation contract

### Nix package and launcher

Add a self-contained package under `packages/anvil-mcp/` which dispatches by platform and selected backend:

- On Linux with `useHeadlessEmacs = false`, build only the NeLisp v0.5.1 `anvil-runtime` crate from the checked-in Cargo lock; install the required NeLisp evaluator sources and compatible anvil.el v1.1.1 modules as immutable runtime data; and wrap the executable with `NELISP_SRC_DIR` and `ANVIL_EL_DIR` fixed to store paths.
- On Linux with `useHeadlessEmacs = true`, build current pinned anvil.el and anvil-ide with `emacs30-nox`; provide `anvil-headless-emacs` and the same `anvil-mcp` command; load the complete configured optional module set; fail startup if any requested module or required runtime is unavailable; authenticate private runtime/state roots, nested worker directories, and socket ownership; establish a process-wide private umask; hold daemon-lifetime locks on both runtime and state identities; prune stale runtime temp/worker trees only after both locks; isolate root and worker state; and mirror typed registrations into the main registry so one static MCP definition exposes all 89 configured tools.
- On Darwin with `useDedicatedDarwinEmacs = false`, invoke the existing packaged `anvil-stdio.sh` bridge with an `emacsclient` that reaches the interactive Emacs socket.
- On Darwin with `useDedicatedDarwinEmacs = true`, reuse the pinned MacPort Emacs while loading the pinned Anvil and anvil-ide closures in `anvil-headless-emacs`; default to one supervised daemon per logical MCP bridge; key every instance by bridge process generation and packaged runtime generation; when `usePerAgentDaemon = false`, install a GUI-domain launchd agent, set exactly `ANVIL_EMACS_LOCK_CONFLICT_STATUS=75` and `ANVIL_EMACS_USE_SYSTEM_LOG=1`, and route startup diagnostics through the bounded macOS system logger; isolate every daemon's socket, schema cache, root state, and worker state from the interactive session and from other clients; and expose the unified 89-tool main registry.
- In every dedicated per-agent backend, keep the bridge process alive across root replacement; publish authenticated generation-aware status and bounded private diagnostics; inject the exact root socket into child environments; reject same-root recursive transport; keep the root heartbeat deadline independent of asynchronous jobs; and kill the Anvil-owned guarded root process group when event-loop progress stops. Worker subprocesses are an explicit offload facility, not evidence that ordinary MCP handlers execute off-root.
- `anvil-mcp --server-id=anvil` is valid for every backend. Darwin and headless Linux also accept `emacs-eval`. NeLisp rejects claims of a live Emacs evaluator.
- Expose focused package and check attributes for each supported backend and platform, plus separate dedicated fast-smoke and 25-cycle persistent-soak checks; the fast check is not soak evidence.

### Shared Home Manager integration

Add a focused `config/anvil.nix` module, import it from `config/johnw.nix`, define the backend and topology Boolean selectors, instantiate the selected package directly, and contribute it to `home.packages`. Dedicated mode defaults to per-owning-process supervision and therefore installs no global service. With `usePerAgentDaemon = false`, Linux installs one host-neutral systemd user service and Darwin installs one GUI-domain launchd agent. Every topology derives hostname and runtime paths when it starts.

### promptdeploy integration

Change source definitions rather than generated agent configuration:

- `mcp/anvil.yaml` uses `anvil-mcp --server-id=anvil` and selects Hera, Clio, and every configured Linux host group on which the shared Nix module installs the launcher.
- Active client deployment uses no second `anvil-tools`/`emacs-eval` registration. Dedicated mode already mirrors the typed surface into `anvil`, while NeLisp exposes its supported standalone surface through that same stable name.
- Deployment and status compare the rendered named MCP entry semantically, not only a manifest hash. A current manifest may not hide a stale, missing, or manually changed Anvil entry. The Home Manager activation is fail-closed and pinned to the packaged promptdeploy implementation; it never reads or reports unrelated client entries or credentials.
- The Anvil skill distinguishes Darwin live mode, Linux headless mode, and NeLisp mode; probes capabilities rather than assuming server prefixes; applies live-buffer safety only when a live Emacs backend exists; and names the exact configured surfaces.
- Documentation describing remote Claude MCP deployment is brought into accord with the existing SSH-stdin merge implementation.

No renderer or schema change is warranted unless the stable launcher contract proves incapable of normalizing the backends.

## Definition of Done

Completion is established only when every item below has direct current-state evidence.

1. The standalone package pins the exact NeLisp/anvil.el compatibility revisions above, uses the checked-in Cargo lock, builds `anvil-runtime` from source, and includes the ARM `c_char` portability correction.
2. The NeLisp runtime closure on both Linux architectures contains no path whose package name is Emacs.
3. Native bounded MCP transcripts on Vulcan ARM64 and Andoria-08 AMD64 exit cleanly; return protocol `2024-11-05`; return exactly 42 unique tools; reject a sole `hello` registry; contain no `bootstrap failed` diagnostic; and successfully call both `file-exists-p` and `shell-run`.
4. The headless package builds natively on both Linux architectures. A bounded two-daemon transcript for each returns exactly 76 direct typed tools and 89 unique unified main tools, waits through a daemon-start race, successfully exercises Elisp, typed file and Org operations, semantic indexing/search, and isolated worker subprocess environments, then shuts down cleanly.
5. The headless service and launcher agree on deterministic, host-qualified platform socket roots even when their inherited environments differ. Tests with distinct hostnames cannot collide; root and worker caches are distinct; and all mutable state resolves outside the shared NFS home.
6. The interactive Darwin launcher reaches the current live Emacs daemon: the main registration exposes 13 eval/IDE tools and the typed registration exposes 65 tools. The dedicated Darwin branch starts two simultaneously isolated test daemons, returns 89 unified main tools and 76 direct typed tools, handles real eval/file calls, stops its worker pools on exit, and leaves the interactive daemon responsive and unchanged.
7. Both generic Linux Home Manager evaluation outputs contain the default selected package; they are not host switch targets. Evaluation of the actual Vulcan, VPS, and Andoria-08 consumer configurations with the local `nix-config` override contains the host-selected package. Both backend Boolean values evaluate. Dedicated per-agent mode omits global services; with `usePerAgentDaemon = false`, Linux contains the systemd user service and Darwin contains the GUI-domain launchd agent.
8. Nix formatting, statix, deadnix, repository flake checks, focused package builds, and relevant Home Manager evaluations pass through the existing environment without `nix develop`.
9. promptdeploy validation passes; focused selection tests prove the unified `anvil` server reaches every supported coding-agent target and the retired `anvil-tools` entry is removed everywhere; scratch rendering proves the correct Claude, Codex, Droid, and OpenCode forms, including exact 540-second startup and tool deadlines; and the complete promptdeploy flake check passes.
10. No rendered MCP command contains `/Users/johnw`, `/tmp/johnw-emacs/server`, or a Nix store path. The command is the bare `anvil-mcp`.
11. The Anvil skill accurately states which tools are present in each backend, does not require `emacs-eval` before using standalone tools, and explains that dedicated Linux or Darwin daemons expose the configured typed surface through the main registration.
12. Each logical work commit has a separate fess audit; all verified findings are addressed; no current non-hidden partner observation remains actionable; the final work commit receives a final audit; and each repository is current with its upstream base locally.
13. User-owned changes and unsaved Emacs buffers remain intact. In particular, no disk edit overwrites an unsaved promptdeploy buffer.
14. One top-level Codex session, one internal Codex agent with its own MCP transport, one Claude session, and a second concurrent client each resolve to distinct generation-qualified root sockets. Hanging one root does not delay liveness or a real request on any other root.
15. Adversarial runtime tests cover a non-yielding synchronous form, same-root recursive shell transport, interrupted shell execution, an externally executed asynchronous form, daemon crash during readiness, daemon crash after dispatch, bridge/client exit, supervisor exit, and package-generation rollover. Every case terminates within its declared budget, never replays a dispatched mutation, retires the known Anvil-owned guarded identities exercised by that case, and either recovers behind the existing MCP pipe or returns a bounded structured error.
16. A standalone persistent-soak check performs at least 25 recovery cycles plus concurrent ordinary file, Org, Git, and Elisp calls, proves that a yielding call can exceed the old 20-second deadline while retaining the same root PID, and interrupts production `main` before, during, and after bridge acquisition plus during finalization, with partial latency reporting and attempt-all signal-safe bridge cleanup. It leaves no stale leases, sockets, supervisors, daemons, workers, or duplicated mutations and shows no unbounded latency growth. The bounded dedicated fast smoke remains a separate gate and cannot substitute for this soak. Current Hera Codex and Claude clients then pass a concurrent soak after complete OS-process restarts; a logical session resume alone is not accepted as activation evidence.
17. The same package and supervisor tests pass on Darwin ARM64, Vulcan ARM64 Linux, and the shared-home AMD64 Linux topology used by Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server. Host-qualified local state remains non-conflicting across the shared NFS home.

## Verification boundaries

A successful build is insufficient evidence for runtime behavior; an initialize response is insufficient evidence for a real registry; and a source diff is insufficient evidence for deployment selection. Each claim is therefore proved at its own boundary: package closure, native MCP transcript, headless daemon, socket/state resolution, Home Manager option evaluation, actual consumer graph, rendered client configuration, live Darwin bridge, and independent audit.

## 2026-07-23 agent-deck session-lifecycle amendment

The user has made the live agent-deck session the tenancy bound for dedicated
Anvil roots. A current census found 13 Anvil-bearing agent-deck session IDs but
40 live transports, each with an attributable exact external-owner generation
and bridge/root tree. There were no orphaned roots: the former per-owner design
itself produced the excess. For agent-deck-managed clients, this section
supersedes the per-logical-bridge and package-build-generation tenancy language
in the Objective, Standing constraints, Darwin implementation contract, and
Definition of Done item 14.
Unmanaged clients retain the exact-owner, per-bridge fallback.

Agent-deck opts a bridge into session sharing with a syntactically valid
`AGENTDECK_INSTANCE_ID` marker. Malformed marker presence fails closed; marker
absence selects the unmanaged fallback. The managed root key is derived from
the current UID, the complete validated instance ID, and the stable
`anvil-agentdeck-session-protocol-v1` epoch. The host-qualified runtime path
remains an additional isolation boundary. Compatible package rebuilds and
source-revision updates therefore join the existing session root instead of
splitting it. Only a deliberate incompatible protocol-epoch bump (represented
by the test-only generation salt), a distinct session ID, UID, or host creates
a distinct managed root.

Each bridge records two exact process generations in its own authenticated
lease: the bridge PID/start identity and that transport's external-owner
PID/start identity. The shared root is not owned by the first bridge's creator.
The supervisor validates every lease against its own recorded bridge and owner,
so one owner or bridge exiting removes only that lease while any surviving
sibling keeps the same supervisor, root Emacs, and worker pool alive.

Admission and retirement serialize on one persistent, private per-session gate
outside the disposable runtime and state trees. A bridge holds the gate while
it prepares or repairs the instance, prunes stale state, and publishes its
lease. After the grace period with zero live leases, the supervisor acquires
the same gate and rechecks the lease set. A newly admitted sibling cancels
retirement; otherwise the supervisor stops and finalizes its daemon and
workers, publishes terminal status, attempts authenticated removal of the
session runtime, state, and creator records, and exits. The empty gate inode is
intentionally retained so every later admission and retirement continues to
use one lock namespace; it is synchronization metadata, not live session
state. Reclaiming old gates safely requires a separate host-wide namespace
lock. If removal cannot complete, attributable remnants remain available for a
later identity-checked safe prune. Admission can therefore never attach to a
root or directory tree actively being retired.

Cross-session pruning uses that same target-session gate for staging cleanup,
identity revalidation, and destructive removal. Because a bridge already holds
its own session gate while pruning siblings, it only attempts each target gate
once without waiting and skips a contended or unsafe target. It likewise only
attempts the target supervisor lock. Concurrent sessions therefore defer
cleanup instead of deadlocking or pruning a root during admission.

The outer bridge installs its `SIGTERM`, `SIGINT`, and `SIGHUP` handler before
entering the transaction, rather than only around steady-state stdio. A first
signal unwinds validation, admission, readiness, stdio, or finalization into
the same bounded cleanup path; subsequent signals cannot interrupt cleanup.
Once a lease has been published, finalization retries its removal and lifecycle
probes. The final Anvil bridge performs an internal bounded wait for the
supervisor and daemon identities it observed and for private tree removal. This
is a fail-closed Anvil optimization, not a process-tree retirement receipt for
an external client.

Agent Deck supplies the validated session identity and stops its own outer
launcher or transport. Anvil validates bridge and owner leases and, after the
final live lease and grace period, owns bounded eventual retirement of its
supervisor, root Emacs, workers, sockets, and disposable private runtime/state.
Agent Deck neither inspects nor signals internal Anvil process identities, and
its transition does not claim synchronous retirement of an arbitrary
descendant tree. A surviving sibling lease keeps the same canonical session
root; a later admission is serialized against any retirement already in
progress.

Additional completion evidence is mandatory:

18. Unit coverage reproduces the observed distribution of 40 distinct exact
    owner/bridge generations over 13 instance IDs and proves exactly 13 managed
    keys, supervisors, roots, locks, runtime trees, and state trees while all
    40 leases are live. Losing one owner preserves its session's remaining
    leases and root; losing the final owner retires only that session. The same
    tests prove compatible builds share a key, an explicit incompatible epoch
    does not, and unmanaged sibling owners remain distinct.
19. The packaged smoke proves two real transports in distinct outer owner
    processes but with one `AGENTDECK_INSTANCE_ID` share one supervisor, root,
    and worker pool. Signalling one outer launcher root removes only its exact
    lease; signalling the final launcher is followed by bounded eventual
    retirement of the known Anvil-owned supervisor, root, workers, sockets, and
    private runtime/state under normal cleanup. Failure-path tests retain
    attributable remnants for later safe pruning. Admission/retirement overlap
    tests exercise both lock orderings, and transaction-wide signal tests cover
    preparation, readiness, steady state, and finalization.
20. Cross-repository integration proves Agent Deck supplies a stable validated
    instance identity and that stopping its outer launcher removes that
    transport's lease. Nix/Anvil checks then prove sibling preservation and
    final-lease cleanup of the Anvil-owned subtree. No test or implementation
    depends on Agent Deck enumerating or signalling internal Anvil PIDs.
21. After activation and complete client-process restarts on Hera, every live
    Anvil-bearing session is warmed with a real call. The census must then show
    no more than 13 canonical roots for the current 13 sessions, exactly one
    root for each warmed session, no cross-session sharing, no duplicate root
    within a session, and no process or disposable runtime/state entry outside
    the live set. Persistent empty session gates are synchronization metadata,
    are excluded from that disposable-state count, and are audited separately.
    A controlled multi-transport session must additionally pass sibling-exit,
    restart, final-exit, and residue checks.
