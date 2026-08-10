# Operator Command Reference

This directory contains the operational entry points for the Nix configuration
repository. These commands do not form a single safety class. Some only inspect
or build state; others rewrite locks, activate systems, publish revisions, delete
generations, or replace security-sensitive files. The distinctions below are part
of the interface.

Run repository commands from the repository root with its direnv environment
loaded. Commands that activate an external consumer must instead be run from that
consumer's authoritative checkout.

## Principal workflows

| Purpose | Command | Operational boundary |
|---|---|---|
| Update all flake inputs and automatic catalog targets | `make update` | Pulls, validates, signs, switches the current host, and publishes only after validation and activation succeed |
| Inspect every managed source and its executor | `bin/update-overlay --inventory --json` | Read-only catalog validation and machine-readable command routing |
| Run the ordinary commit gate | `lefthook run pre-commit --all-files` | Essential formatting, lint, and fast tests; bounded to two minutes |
| Run low-frequency expensive assurance | `make expensive` | Consumer and native assurance followed by a Darwin build; run the pre-commit gate separately for formatting and static lint |
| Build the complete current Darwin system | `./build system` | Builds without activating; Hera and Clio only |
| Inspect the Pi package version | `nix eval --raw .#packages.$(nix eval --impure --raw --expr builtins.currentSystem).pi.version` | Reports the package selected by this checkout, not necessarily the active binary |
| Preflight publication | `bin/publish` | Performs no push |
| Publish a reviewed signed revision | `bin/publish --publish` | Fast-forward-only publication to both authoritative remotes |

There is presently no correct one-command whole-fleet rollout. Publication,
consumer lock updates, builds, activation, and runtime acceptance remain separate
operations. The legacy bulk commands are identified below and must not be treated
as fleet proof.

## Updating versions and pins

### Complete automatic update transaction

The canonical update is:

```sh
make update
```

This delegates to:

```sh
bin/update --all-inputs --pull --commit --switch --push
```

The transaction updates both flake locks and every automatic source catalog
record under `sources/`. It requires a clean checkout, takes a repository lock,
constructs an isolated candidate worktree, rejects undeclared file changes, runs
the required validation, creates a signed commit, activates the exact candidate,
fast-forwards the checked-out branch, and publishes through `bin/publish`.
Homebrew is intentionally outside this transaction.

The target checkout is selected in this order: `NIX_CONFIG_DIR`; the system
checkout (`UPDATE_AGENTS_SYSTEM_CONFIG_DIR`, default `/etc/nixos`) when that
directory exists — on NixOS hosts it is authoritative and owns the build
lock, and invoking `update` from inside a *different* nix-config checkout on
such a host refuses loudly rather than silently retargeting; the invoking
Git work tree when it is a primary nix-config checkout (it contains
`flake.nix` and `config/ai`, and is not a linked worktree — so `update` run
from an agent worktree cannot pull, activate, and publish a feature branch;
a separate full clone parked on a feature branch is treated as a deliberate
operator context and is honored); and otherwise `~/src/nix`. The resolved
target is printed to stderr before the transaction starts. Set
`NIX_CONFIG_DIR` when the implicit choice would be ambiguous; it overrides
the working directory.

A failure prevents later phases but does not undo completed external effects.
Activation precedes publication. If publication fails, the signed local commit
is deliberately retained for inspection and an explicit retry.

Useful narrower forms are:

```sh
# Validate all flake inputs and automatic targets without changing the checkout.
bin/update --all-inputs --dry-run

# Preview one target owned by the catalog executor.
bin/update-overlay --dry-run llama-swap

# Update that target and leave the reviewed result in the working tree.
bin/update-overlay llama-swap

# Preview one target owned by the transaction executor.
bin/update --target llm-agents --dry-run

# Transaction-owned --target is repeatable.
bin/update --target llm-agents --target hf-xet

# Force a version-capable transaction target.
bin/update --target hf-xet --version VERSION
```

`--switch` and `--push` require `--commit`. `--version` applies only to target
kinds that possess an explicit version or revision projection; plain flake-input
targets do not accept it. The remaining public flags are `--brew`, `--help`, and
the negations `--no-switch` and `--no-brew`, which disable a previously
requested `--switch`/`--brew` (the later flag wins); switching and Homebrew
are already disabled unless requested.

`bin/update-overlay` is the lower-level catalog engine. Its inventory is the
authoritative answer to which manually tracked sources can be updated:

```sh
bin/update-overlay --inventory
bin/update-overlay --inventory --json
bin/update-overlay --inventory --json \
  | jq -r '.packages[] | [.name, .policy, .executor] | @tsv'
bin/update-overlay --all --dry-run
```

Routine coordinated work should use `bin/update`, since it also owns lock updates,
candidate isolation, validation, signing, activation, and publication.

Catalog records with manual update policy are intentionally excluded from the
automatic pass. Inspect each record's `executor` in the JSON inventory. Use
`bin/update --target NAME` for `update` records and `bin/update-overlay NAME` for
`update-overlay` records. There is no unattended command that advances all
manual-policy records.

The public operator options are `--all`, `--dry-run`, `--version`, `--verbose`,
`--inventory`, and `--json`. `--no-build` is retired and returns an error.
Although help also exposes `--sync-flake-projections`, it requires the isolated
candidate environment and a detached linked worktree; it and the five hidden
`--prepare-*` modes are transaction-internal steps used by `bin/update`, not
operator interfaces. Direct target mode updates the owning catalog record;
update-owned targets delegate back to `bin/update`. `--all` covers automatic
targets owned by the lower-level executor, not every catalog record.

## Determining package versions

Questions about a tool's version have four distinct answers: the packaging
substrate revision, the reviewed source revision, the package built by this
checkout, and the binary active in the current profile. For Pi, inspect all
four as follows:

```sh
# Packaging substrate revision pinned for Pi by the root lock. Pi builds from
# the dedicated pi-llm-agents feed; the floating llm-agents input packages the
# other agents and does not build Pi.
jq -r '.nodes["pi-llm-agents"].locked.rev' flake.lock

# Reviewed Pi source revision; flake/ai.nix asserts the packaged version
# agrees with this record.
jq -r '.sources["pi-coding-agent-source-build"].source.args.rev' sources/ai.json

# Version and store output selected by this checkout.
system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix eval --raw ".#packages.${system}.pi.version"; echo
nix eval --raw ".#packages.${system}.pi.outPath"; echo

# Version and store output active in the current shell.
pi --version
realpath "$(command -v pi)"
```

The evaluated package and active binary should agree after a successful switch.
The same evaluation pattern applies to package attributes that expose a `version`
field.

## Building and verification

### Ordinary development

```sh
# The mandatory commit gate.
lefthook run pre-commit --all-files

# Its direct equivalent.
test/bin/quality --tier pre-commit

# Check formatting without rewriting files.
nix fmt -- --check

# List or select individual quality suites.
test/bin/quality --list
test/bin/quality nix-format nix-lint shell-lint python-lint

# Full Python tests and the principal repository package contracts.
make test

# Build the complete Darwin configuration for the current host.
./build system
```

The pre-commit tier has a 120-second envelope. It runs the essential static and
fast-test suites. `nix fmt` or `make format` rewrites tracked Nix and shell
sources; retain `-- --check` when inspection alone is intended. `make test` is
broader but is not a whole-fleet build.

Explicit formatter paths are also supported:

```sh
nix fmt -- path/to/file.nix path/to/script.sh
```

Explicit-path mode always rewrites the named supported files, including untracked
files. It has no check-only form.

The pre-push hook verifies commit signatures:

```sh
lefthook run pre-push --force
test/bin/quality signatures
```

### Portable and low-frequency assurance

```sh
# Evaluate the portable AI flake on every declared system without building.
nix flake check ./config/ai --all-systems --no-build

# Run the aggregate format, lint, evaluation, build, and warning checks.
nix run ./config/ai#check

# Run the expensive repository tier and build the current Darwin system.
make expensive

```

The expensive quality tier has a 30-minute envelope, but `make expensive` then
runs additional Nix builds outside that envelope. It is intended for issue
closeout and periodic assurance, not for every commit. It does not include the
ordinary formatting and static-lint suites, so it complements rather than
replaces the pre-commit gate.

The `config/ai#check` spelling does not isolate every operation to that subflake.
Its format check scans the caller's entire Git tree, and its warning check builds
the caller-root default output. Run it only from the intended checkout.

### Focused builders

The root [`build`](../build) command builds but does not activate:

```sh
./build --help
./build system
./build pkg PACKAGE
./build emacs PACKAGE
./build python PACKAGE
./build haskell PACKAGE
```

It operates on the current Darwin package set and normally creates a `result`
link. Additional arguments after the mode and optional package are passed to
`nix build`. NixOS consumers use their own `/etc/nixos/build` driver instead.

## Publication and fleet activation

### Publication

`bin/publish` is the sole dual-remote publication command:

```sh
bin/publish             # Fetch, verify, and perform push dry-runs.
bin/publish --publish   # Run the gate once and push the signed branch tip.
```

It requires a clean tracked tree at the checked-out branch tip, verifies
signatures, proves that both remotes accept a fast-forward, and reads both remotes
back after publication. It never force-pushes. Two independent remotes cannot
provide atomic publication; the command therefore reports a partial publication
as a failure requiring reconciliation.

`--dry-run` is an explicit spelling of the non-publishing default. `--rev REV`
and `--branch NAME` assert the exact tip to publish. `--help` prints the contract.
Force options are refused rather than forwarded to Git. Untracked files are
permitted because they do not alter the published tree.

### Host-owned activation

Each consumer owns its lock and activation. A published root revision is not an
active configuration until the relevant authoritative checkout has consumed and
activated it.

| Consumer | Authoritative checkout | Build and activation |
|---|---|---|
| Hera | `~/src/nix` | `make switch`; use `make build` separately for build-only evidence |
| Clio | `~/src/nix` on Clio | Fast-forward that checkout, then run `make switch` |
| Vulcan | `/etc/nixos` on Vulcan | Update paired inputs, then run `./build build` and `./build` |
| VPS | `/etc/nixos` on VPS | Update paired inputs, then run `./build build` and `./build` |
| Shared work hosts | `~/.config/home-manager` shared by the four hosts | Update the paired inputs once; realize and retain the closure, then activate it on every host |

The paired external inputs are updated together:

```sh
nix flake update nix-config nix-config-ai
```

Vulcan and VPS must use the consumer-local `./build` script. It owns the build
lock; raw `nixos-rebuild switch` and the generic `switch` helper bypass that
protocol.

On Darwin, `make switch` runs `lock-local` before nix-darwin builds and activates
the selected generation. A preceding `make build` does not re-lock local inputs
and therefore does not, by itself, prove the exact closure that a later switch
will select.

The shared-work rollout covers `andoria-08`, `andoria-t2`, `delphi-3bd4`, and
`gpu-server`. It must realize the candidate once, make the closure resident on
every target, preserve the previous closure for rollback, and activate all four
hosts. The repository does not yet encode that complete sequence as one command.
See [Architecture](../doc/ARCHITECTURE.md#host-registry-and-shared-home-policy).

Evaluation, build, activation, and a successful command lookup are separate
evidence. A fleet change is complete only after every intended host reports the
new generation and the affected executable or service passes a runtime check.

## `bin/` command inventory

| Command | Purpose | Material effects and cautions |
|---|---|---|
| `de [--no-cache] [NIX_ARGS...]` | Create and cache a project direnv development environment | May create `.envrc`, `.envrc.cache`, and product directories; sources `.env` as shell code. `--no-cache` is presently a no-op beyond argument removal. |
| `env-build` | Run injected stdenv configure, build, and check phases | Internal builder exposed by packaging; do not invoke in an ordinary shell. |
| `git-sha OWNER/REPO REV` | Prefetch a Git revision and print its Nix SHA-256 | Invokes `nix-prefetch-git`; intended for source maintenance. |
| `myhost` | Print the locally inferred host class | Resolves through the shared routing library (hera/clio/vulcan/shared-work/vps), using `ipaddr en0` only to disambiguate the two workstations; exits 1 loudly on an unrecognized host. Do not use it as security or deployment authorization. |
| `persona NAME` | Select Claude, Git, and optional GitHub identities | Replaces mutable identity state and `~/.claude`; persona files are sourced shell code. Inspection forms are `--status/-s`, `--list/-l`, and `--env/-e`; `--help/-h` prints usage and exits with status 1. |
| `publish [--publish] [--rev REV] [--branch NAME]` | Preflight or perform dual-remote publication | `--publish` pushes; `--dry-run` and the bare form do not. Never force-pushes. |
| `runemacs [VERSION]` | Start the external Emacs `open` target through `load-env-emacsVERSION` | Depends on the Emacs repository and PATH-provided helper. |
| `switch` | Dispatch activation by host class | Safe for Darwin and shared Home Manager only under their normal ownership rules. Its NixOS branch bypasses the required Vulcan/VPS build-lock wrapper and must not be used there. |
| `u [HOST] MAKE_ARGS...` | Dispatch the configured Makefile for Hera, Clio, or Vulcan | Host identity comes from the shared routing library; other host classes exit 1 with `u: unsupported host class`, and unrecognized hosts exit 1 loudly. On Darwin, first raises launchd and shell file-descriptor limits. It is not a general fleet dispatcher. |
| `update [OPTIONS]` | Run the transactional lock and source-catalog updater | `--target` is repeatable; `--all-inputs`, `--version`, `--dry-run`, `--pull`, `--commit`, `--switch`, `--push`, and `--brew` control the transaction. Without `--dry-run`, validated changes are written back. |
| `update-and-pull` | Find repositories under broad home-directory roots and run a PATH-provided `update` in parallel | Follows symlinks and delegates mutation semantics to an external command; use only as an attended personal maintenance operation. |
| `update-home-manager` | Update, commit the lock, and activate `~/.config/home-manager` | Uses unpinned `home-manager/master`; lacks fail-fast handling and may activate after an update failure. It is not the supported shared-work rollout. |
| `update-overlay [TARGETS...]` | Inspect or update catalog-managed sources | Direct mode updates owning catalog records; some targets delegate to `bin/update`. Prefer the transaction for coordinated work. |
| `update-remote` | Open a Clio and selected Linux consumer update jobs | Legacy and incomplete: it does not await tmux pane results, omits three shared-work hosts, and bypasses the NixOS build-lock wrappers. Do not use as fleet proof. |
| `upgrade [HOST] [--host-only\|--projects-only]` | Combine a host operation with project maintenance | `--help` prints usage. Hera performs the full update transaction, travel/Homebrew tasks, and store signing; Clio builds and switches; Linux behavior delegates to `switch` and inherits its NixOS limitation. |
| `upgrade-all` | Run broad repository, synchronization, host, and project maintenance | Legacy umbrella operation; a failed Hera host upgrade (`upgrade hera --host-only`) aborts before `pushme` and `update-remote`, while project maintenance runs last and is diagnostic only. Inherits `update-remote` limitations; it is not a reliable all-host transaction. |
| `upgrade-projects` | Reconfigure a fixed list of projects and update selected language dependencies | Sources project `.envrc` files, may rewrite Cargo locks, truncates logs, and deletes pip and uv caches. |
| `yubikey-switch MODE` | Replace active GnuPG key files for a YubiKey arrangement | `MODE` is `restore` or a backup suffix. It overwrites private-key files, kills GPG agents, probes the card, updates a Git remote, and may create PAM challenge state; the restore volume check and read path presently disagree. Inspect before use. |

[`lib/host-routing.sh`](lib/host-routing.sh) is an internal sourced library. It
normalizes host identities and maps them to flake output names; it is not a
standalone command.

## Make target inventory

| Target | Purpose and caution |
|---|---|
| `help` | Print the short operator summary; this README is the complete reference. |
| `all` | Alias for `switch`; it activates the current Darwin configuration. |
| `TARGET-all` | Run `TARGET` locally and then through `u` on every host in `REMOTES`; remote source synchronization is not implied. The pattern accepts destructive targets, so inspect `TARGET` and `REMOTES` before use. |
| `test` | Run the full Python suite and build four principal package checks. |
| `expensive` | Run expensive assurance and build the current Darwin system. |
| `tools` | Print selected environment values and tool resolution. |
| `repl` | Open a Nix REPL for the current Darwin package set. |
| `verify-inputs` | Detect local Git input states that can produce divergent NAR hashes. |
| `lock-local` | Verify and refresh `file://` Git inputs in the root lock. |
| `build` | Build the current Darwin system without switching; removes the resulting `result` link. |
| `switch` | Refresh local-file inputs and activate the current Darwin system. |
| `update` | Run the complete pull, update, validate, sign, switch, and publish transaction. |
| `update-projects` | Run `nix flake update` in every project listed by `~/.config/projects`; does not commit or publish. Legacy fail-open loop: a failed `cd` may run the update in the repository root and an earlier failure may be masked. |
| `upgrade-tasks` | Run `travel-ready`, then upgrade Homebrew packages; inherits the `travel-ready` path-safety limitation. |
| `upgrade` | Under serial Make, run `update` and then `upgrade-tasks`; the prerequisites are not explicitly ordered and may run concurrently under `make -j` or inherited parallel `MAKEFLAGS`. Do not invoke this target in parallel. |
| `changes` | Run an external `changes` command across configured and fixed repositories. A failed `cd` may run it in the wrong directory, and loop failures may be masked. |
| `copy` | Copy the current profile closure and per-project direnv build inputs to each host in `REMOTES` via `nix copy`. Loop failures may be masked, matching the other legacy loops above. |
| `check` | Run `nix store verify --no-trust --repair --all`; it disables trust verification and may repair, and therefore mutate, store paths. |
| `sizes` | Report the filesystem containing `/nix`. |
| `clean` | Intended to retain `MAX_AGE` user/system generations and collect paths older than `MAX_AGE` days. The system-profile deletion is unsudoed and can fail after partially deleting user generations but before garbage collection; do not use until repaired. |
| `scour` | Delete language and package-manager caches. It is not declared phony; a filesystem entry named `scour` suppresses the recipe. |
| `purge` | Intended to depend on `scour`, retain one generation, and delete old paths. It inherits the unsudoed system-profile failure and can stop after partial deletion; a filesystem entry named `scour` can also suppress cache deletion. Do not use until repaired. |
| `sign` | Sign every store path with the configured private Nix signing key. |
| `format` | Rewrite tracked Nix and shell files through the quality authority. |
| `lint` | Run the entire default quality suite, including full Python tests; it is broader than its name suggests. |
| `travel-ready` | Delete both `.envrc` and `.envrc.cache`, invoke an external `clean`, and regenerate configured project environments. A failed `cd` can run later commands in the wrong directory and earlier loop failures may be masked. |

`clean`, `scour`, `purge`, `sign`, `travel-ready`, and
all activation targets require deliberate operator review. Their names do not
reduce their effects.

## Flake applications

The root and portable flakes export the same application names. Invoke them as
`nix run .#NAME` or `nix run ./config/ai#NAME` from the intended checkout.

| Application | Purpose |
|---|---|
| `format` | Rewrite supported Nix and shell sources discovered from the caller's Git checkout; accepts `--check` for inspection only. |
| `format-check` | Check those discovered sources without rewriting. |
| `lint` | Lint the portable AI Nix paths and AI shell checks. |
| `test` | Run portable flake show and evaluation checks; not the full repository suite. |
| `build-check` | Build the portable default package without a result link. |
| `no-warnings` | Build with evaluation warnings treated as fatal. |
| `check` | Run the five configured checks in sequence; some operate on the caller's root checkout. |
| `default` | Alias for `check`. |

The applications discover the repository from the caller's current Git checkout
unless `AI_NIX_ROOT` is set. Running them from an unrelated checkout can therefore
target the wrong tree.

## Evidence and safety

- A successful evaluation proves configuration construction, not a build.
- A successful build proves realization, not activation.
- A successful activation proves generation selection, not client or service health.
- A successful publication proves remote Git state, not consumer adoption.
- Secret values, decrypted material, request payloads, and session transcripts must never enter logs or generated files.
- Before any commit, inspect both `git status` and the exact staged paths.

The detailed ownership and rollout contracts are maintained in
[`doc/ARCHITECTURE.md`](../doc/ARCHITECTURE.md).
