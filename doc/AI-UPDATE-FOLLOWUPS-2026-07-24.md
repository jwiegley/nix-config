# AI update follow-up report

Date: 2026-07-24

## Current transaction

The current update remains focused on local validation and fleet propagation:

1. Finish reconciling the updated agent pins and source hashes.
2. Run the complete local pre-commit gate.
3. Build and switch Hera.
4. Publish `nix-config` to Gitea and GitHub.
5. Replace the Vulcan and Andoria `ai-nix` inputs with the matching
   `nix-config?dir=config/ai` input, regenerate their locks, and build/switch.
6. Push the final root revision, then SSH to Clio and run `switch`.

No CI expansion is part of this transaction.

## Findings completed during the update

- `update-agents` now updates only the declared AI inputs. A dirty local source
  checkout can no longer cause a bare `nix flake update` to silently leave the
  root lock unchanged.
- Codex 0.145.0 and Pi 0.82.0 version oracles are updated. The Pi renderer ABI
  patch was rebased against the 0.82.0 release bytes, guarded by refreshed
  source digests, and exercised by the installed-source test suite.
- Root and portable AI locks are synchronized, with an evaluation-time
  coherence check for every shared direct input.
- External consumers can supply the portable AI overlay while the source overlay
  loader restores the caller's own input set afterward.
- `config/packages.nix` uses `inputs.nix-ai` when supplied and otherwise degrades
  to unwrapped agent packages when the local AI input closure is incomplete.
- The unsupported `x86_64-darwin` root output was removed, allowing whole-flake
  evaluation over the three maintained systems.
- The duplicate `no-warnings` check now aliases `lint` and is covered by the
  compatibility contract.
- The bridge oracle derivation explicitly allows Darwin loopback networking,
  owns the child process group, and bounds pipe reads and shutdown.
- Updated EmacsWiki source hashes were reviewed for process/network primitives
  before acceptance.

## Deferred repository work

### Local quality gates

- Investigate the ARM64 Linux Home Manager smoke failure in
  `statusline-command-test.py` (`jq` invocation count remained zero). The native
  ARM64 Pi gallery itself passes.
- Restore genuine x86_64 Linux execution of the expanded Pi gallery; evaluation
  passes, but no reachable native x86 builder is currently available.

### CI -- explicitly deferred

- Build `agent-wrappers`, `agent-resources`, `lint`, and `tests` in addition to
  the Pi gallery on native CI runners.
- Replace the CI shell-script allowlist with the local bash-shebang discovery
  loop so future scripts cannot escape linting.
- Ensure every Gitea landing is mirrored to GitHub if GitHub CI is expected to
  gate it.

### Remaining consumer migration

- After Vulcan and Andoria-08, migrate VPS and the auxiliary Git-AI VM consumer
  to paired `nix-config` source and `nix-config?dir=config/ai` revisions.
- Reconcile the secondary `~/src/nixos` Vulcan checkout so it cannot later
  reintroduce the retired `ai-nix` input.
- Remove Vulcan's obsolete local `agent-deck` package mirror once the portable
  overlay is active; the integrated overlay already uses the required Go 1.26
  builder.

### Previously requested Pi and review work

- Package and install `arpagon/pi-rewind` through the immutable Pi gallery.
- Compare `xec-abailey/pi-litellm` with the installed `pi-provider-litellm`
  using source, behavior, credential, discovery, and maintenance evidence.
- Add the `heavy-review` command coordinating deep, Alexey-discipline,
  ponytail, dead-code, and comment audits across repository, PR, and working-tree
  scopes.
- Run the requested whole-repository deep review, Alexey-discipline review,
  ponytail review, dead-code elimination, and exhaustive comment audit.

### Native Nix data policy

- Inventory tracked YAML/JSON documents and embedded YAML/JSON strings.
- Replace authored data with native Nix expressions where practical, generating
  external formats only at evaluation or build time.
- Treat unavoidable protocol artifacts such as `flake.lock`, upstream package
  locks, and GitHub workflow YAML as explicit exceptions or generate them from a
  single Nix-owned source where tooling permits.
