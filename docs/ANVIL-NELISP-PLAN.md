# Anvil Fleet Backend Plan

Status: frozen on 2026-07-11 and amended the same day in response to explicit follow-up requirements. This document fixes the objective and the evidence required for completion. It may be amended to record a stricter requirement or a newly discovered fact; it is not to be weakened to accommodate an implementation.

## Objective

> Right now in this repository we build anvil.el for use here on this macOS machine with the same Emacs that I use for coding and development. If you research the anvil.el project at https://github.com/zawatton/anvil.el, you'll see that it has a "NeLisp" approach for running on system that may not have Emacs. I want to use this feature for all of the Linux machines that this configuration is built on, so that I can make Anvil MCP available to all of my agents on all platforms. This also implies some changes to ~/src/promptdeploy so that the next time I deploy this MCP server will be made available everywhere that Anvil is running. $command-wiggum

The user subsequently made ARM64 Linux on Vulcan and AMD64 Linux on Andoria-08 explicit requirements, asked whether a full headless-Emacs backend could coexist safely on the shared-home Andoria family, and required one Linux Boolean to select either the NeLisp or headless-Emacs-daemon approach. The user then required an independent macOS Boolean selecting the current interactive development Emacs or a second dedicated headless Anvil Emacs, because agent traffic can intermittently lock the interactive Hera session.

The work therefore comprises one cross-repository contract: Nix supplies a reproducible launcher and the platform-specific backends; two independent Home Manager Booleans select the Linux and Darwin behavior; promptdeploy registers one stable launcher wherever the corresponding runtime is present; and the deployed Anvil skill describes the capabilities actually offered by each backend.

## Authoritative baseline

The current worktrees and live consumers are authoritative. The following upstream sources were checked on 2026-07-11:

- anvil.el master/version 1.3.0 at `574568a95a2bd8fceca6c9cd3bec0f94ecf0e6a9`;
- NeLisp main at `7f501835d30270c428613a8fb314d59bbec01023`;
- NeLisp v0.5.1 at `f753209d53b372933b829345fe4373acad67bcb5`; and
- anvil.el v1.1.1 at `d50ce32b71c5fa46da3aa661481c8be44fee4f97`.

Current upstream documentation describes a Rust standalone path that has since been removed from NeLisp main. The later pure-Elisp launcher in anvil.el master does not match the current NeLisp executable path or command line, carries an unproved and materially smaller tool surface, and records a five-to-seven-minute cold load. The standalone branch therefore adopts the last reproducible released compatibility pair: NeLisp v0.5.1 with the byte-identical Anvil modules from anvil.el v1.1.1. This is a deliberate compatibility pin, not an assertion that current heads are interoperable.

The dedicated branch uses current pinned anvil.el 1.3.0 and the separately pinned anvil-ide package. Linux pairs them with a Nix-built Emacs 30 no-X package; Darwin reuses the pinned MacPort Emacs while running a separate minimal daemon. The live interactive Mac remains the compatibility baseline at 12 `anvil` eval/IDE tools plus 65 `emacs-eval` typed tools. The dedicated daemon loads the complete configured optional set `(ide elisp sexp semantic sqlite pdf cron state shell-filter context)`, yielding 76 direct typed tools. It publishes those typed tools into the main `anvil` registry as well, producing one 88-tool registration compatible with static promptdeploy configuration; the direct typed registry remains available for diagnosis and worker offload.

## Standing constraints

- Linux support covers native `aarch64-linux` on Vulcan and native `x86_64-linux` on Andoria-08.
- `johnw.anvil.useHeadlessEmacs` is the Linux selector. It defaults to `false`: false selects NeLisp; true selects the dedicated headless Emacs daemon.
- `johnw.anvil.useDedicatedDarwinEmacs` is the independent macOS selector. It defaults to `false`: false uses the existing interactive development Emacs; true uses a separate dedicated daemon.
- The NeLisp runtime closure contains no Emacs executable or Emacs package. The Linux headless closure deliberately contains `emacs30-nox` and current pinned anvil.el.
- Both Darwin branches reuse the Emacs package built by `overlays/10-emacs.nix`; the dedicated branch is a separate process with `-Q`, minimal Anvil initialization, and isolated state.
- Every actual Linux consumer imports `config/johnw.nix`; VPS deliberately omits `config/packages.nix`, while Vulcan and VPS omit the Emacs overlay. The shared Home Manager module is consequently the canonical installation point, and the headless package may not depend on importing the large Emacs overlay.
- Vulcan is configured by `/etc/nixos/flake.nix`. Andoria-08 and its siblings are configured by the shared `~/.config/home-manager/flake.nix`.
- Andoria-08, Andoria-t2, Delphi-3bd4, and gpu-server share the same NFS home and Home Manager profile. One identical unit must derive the actual short hostname at runtime; it must not trust the Andoria flake's hard-coded `hostname = "andoria-08"`.
- Headless sockets and mutable Emacs/Anvil state are host-local. Linux defaults to `/run/user/$UID/anvil-emacs/$SHORT_HOST/emacs/server`; Darwin defaults to `/tmp/anvil-emacs-$UID/$SHORT_HOST/emacs/server`. Durable state is beneath `/var/tmp/anvil-emacs-$UID/$SHORT_HOST`, with distinct root and worker Emacs directories, schema caches, SQLite databases, and native-comp caches. Temporary root and worker trees live beneath the host-qualified runtime root; Linux prunes stale temporary trees only after acquiring a daemon-lifetime singleton lock. Every runtime/state component must be a real `0700` directory owned by the current user, and sockets may not be symlinks. No mutable daemon state or server file is placed on NFS.
- The standalone server is not permitted to pass by falling into upstream's one-tool `hello` placeholder registry. Exact tool-surface and behavioral checks are mandatory.
- promptdeploy stores only a PATH-stable launcher command. Nix store paths, user-specific home paths, Darwin socket paths, source downloads, and build steps remain outside MCP definitions.
- No deployment, Home Manager activation, NixOS switch, push, or rewritten shared history is part of this autonomous loop. Those are separate, human-gated operations.
- No SOPS secret is read or decrypted.
- Commands run in the environment already supplied by the worktree and its direnv state. `nix develop` is not used.

## Implementation contract

### Nix package and launcher

Add a self-contained package under `packages/anvil-mcp/` which dispatches by platform and selected backend:

- On Linux with `useHeadlessEmacs = false`, build only the NeLisp v0.5.1 `anvil-runtime` crate from the checked-in Cargo lock; install the required NeLisp evaluator sources and compatible anvil.el v1.1.1 modules as immutable runtime data; and wrap the executable with `NELISP_SRC_DIR` and `ANVIL_EL_DIR` fixed to store paths.
- On Linux with `useHeadlessEmacs = true`, build current pinned anvil.el and anvil-ide with `emacs30-nox`; provide `anvil-headless-emacs` and the same `anvil-mcp` command; load the complete configured optional module set; fail startup if any requested module or required runtime is unavailable; authenticate private runtime/state roots and socket ownership; hold a daemon-lifetime singleton lock; prune stale runtime temp trees after locking; isolate root and worker state; and mirror typed registrations into the main registry so one static MCP definition exposes all 88 configured tools.
- On Darwin with `useDedicatedDarwinEmacs = false`, invoke the existing packaged `anvil-stdio.sh` bridge with an `emacsclient` that reaches the interactive Emacs socket.
- On Darwin with `useDedicatedDarwinEmacs = true`, reuse the pinned MacPort Emacs while loading the pinned Anvil and anvil-ide closures in `anvil-headless-emacs`; install a user-domain launchd agent; isolate its socket, schema cache, root state, and worker state from the interactive session; and expose the unified 88-tool main registry.
- `anvil-mcp --server-id=anvil` is valid for every backend. Darwin and headless Linux also accept `emacs-eval`. NeLisp rejects claims of a live Emacs evaluator.
- Expose separate focused flake package and check attributes for NeLisp and headless Linux on both architectures, plus the Darwin launcher.

### Shared Home Manager integration

Add a focused `config/anvil.nix` module, import it from `config/johnw.nix`, define both Boolean selectors, instantiate the selected package directly, and contribute it to `home.packages`. Linux headless mode conditionally installs one host-neutral systemd user service; Darwin dedicated mode installs one launchd agent. Both derive hostname and runtime paths when they start.

### promptdeploy integration

Change source definitions rather than generated agent configuration:

- `mcp/anvil.yaml` uses `anvil-mcp --server-id=anvil` and selects Hera plus every configured Linux host group on which the shared Nix module installs the launcher.
- `mcp/anvil-tools.yaml` uses `anvil-mcp --server-id=emacs-eval` and remains limited to the configured macOS targets (Hera/local and Clio); Linux NeLisp rejects that server ID, while every dedicated main registration already contains the typed surface.
- The Anvil skill distinguishes Darwin live mode, Linux headless mode, and NeLisp mode; probes capabilities rather than assuming server prefixes; applies live-buffer safety only when a live Emacs backend exists; and names the exact configured surfaces.
- Documentation describing remote Claude MCP deployment is brought into accord with the existing SSH-stdin merge implementation.

No renderer or schema change is warranted unless the stable launcher contract proves incapable of normalizing the backends.

## Definition of Done

Completion is established only when every item below has direct current-state evidence.

1. The standalone package pins the exact NeLisp/anvil.el compatibility revisions above, uses the checked-in Cargo lock, builds `anvil-runtime` from source, and includes the ARM `c_char` portability correction.
2. The NeLisp runtime closure on both Linux architectures contains no path whose package name is Emacs.
3. Native bounded MCP transcripts on Vulcan ARM64 and Andoria-08 AMD64 exit cleanly; return protocol `2024-11-05`; return exactly 42 unique tools; reject a sole `hello` registry; contain no `bootstrap failed` diagnostic; and successfully call both `file-exists-p` and `shell-run`.
4. The headless package builds natively on both Linux architectures. A bounded two-daemon transcript for each returns exactly 76 direct typed tools and 88 unique unified main tools, waits through a daemon-start race, successfully exercises Elisp, typed file and Org operations, semantic indexing/search, and isolated worker subprocess environments, then shuts down cleanly.
5. The headless service and launcher agree on deterministic, host-qualified platform socket roots even when their inherited environments differ. Tests with distinct hostnames cannot collide; root and worker caches are distinct; and all mutable state resolves outside the shared NFS home.
6. The interactive Darwin launcher reaches the current live Emacs daemon: the main registration exposes 12 eval/IDE tools and the typed registration exposes 65 tools. The dedicated Darwin branch starts two simultaneously isolated test daemons, returns 88 unified main tools and 76 direct typed tools, handles real eval/file calls, stops its worker pools on exit, and leaves the interactive daemon responsive and unchanged.
7. Both generic Linux Home Manager outputs contain the selected package. Evaluation of the actual Vulcan, VPS, and Andoria-08 consumer configurations with the local `nix-config` override contains it. Both Linux Boolean values evaluate; the true branch contains the systemd user service and the false branch does not. Both Darwin Boolean values evaluate; the true branch contains the launchd agent and the false branch does not.
8. Nix formatting, statix, deadnix, repository flake checks, focused package builds, and relevant Home Manager evaluations pass through the existing environment without `nix develop`.
9. promptdeploy validation passes; focused content-selection tests prove the main server reaches every supported coding-agent target and the split typed server reaches Hera only; scratch rendering proves the correct Claude, Codex, Droid, and OpenCode forms; and the complete promptdeploy flake check passes.
10. No rendered MCP command contains `/Users/johnw`, `/tmp/johnw-emacs/server`, or a Nix store path. The command is the bare `anvil-mcp`.
11. The Anvil skill accurately states which tools are present in each backend, does not require `emacs-eval` before using standalone tools, and explains that dedicated Linux or Darwin daemons expose the configured typed surface through the main registration.
12. Each logical work commit has a separate fess audit; all verified findings are addressed; no current non-hidden partner observation remains actionable; the final work commit receives a final audit; and each repository is current with its upstream base locally.
13. User-owned changes and unsaved Emacs buffers remain intact. In particular, no disk edit overwrites an unsaved promptdeploy buffer.

## Verification boundaries

A successful build is insufficient evidence for runtime behavior; an initialize response is insufficient evidence for a real registry; and a source diff is insufficient evidence for deployment selection. Each claim is therefore proved at its own boundary: package closure, native MCP transcript, headless daemon, socket/state resolution, Home Manager option evaluation, actual consumer graph, rendered client configuration, live Darwin bridge, and independent audit.
