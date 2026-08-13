# Nix Configuration: Architecture and Operations Guide

## Purpose and scope

This guide explains the configuration family rooted in `nix-config`: which
repository owns each decision, how the Darwin, NixOS, and standalone Home
Manager consumers adopt that decision, and how a reviewed source revision
becomes an active configuration. It is a reference to the standing design and
operating contract. It does not record which revision is presently deployed,
whether a host is reachable, or which work item is in progress.

Current work has one authority: `obr`, whose tracked projection is
`doc/PLAN.org`. Completed work belongs in Git history. Neither this guide nor a
separate status or handoff document is a second current-work ledger.

The principal source authorities for this guide are `README.md`,
`doc/ARCHITECTURE.md`, `bin/README.md`, `config/hosts/registry.nix`, and
`config/nix-trust.nix`. Compare observed Nix-owned or generated machine state
with the exact source revision selected by that consumer, not automatically
with the newest source checkout. An unexplained difference is evidence of
incomplete adoption or activation; deliberate consumer lag is not. Neither is
a reason to edit generated machine state by hand. Intentionally mutable runtime
state may differ.

## 1. The system in one view

The arrangement is deliberately asymmetric. One repository owns shared
implementation, while each consumer retains its own lock, activation, rollback,
and mutable state.

```text
                         /Users/johnw/src/nix
                   shared implementation authority
                                  |
              +-------------------+-------------------+
              |                                       |
       root flake and modules                  config/ai subflake
       Darwin systems, shared                 portable packages,
       Home Manager policy                    overlays, checks, apps
              |                                       |
              +-------------------+-------------------+
                                  |
               consumer-owned paired revision adoption
                                  |
       +----------------+---------+---------+----------------+
       |                |                   |                |
     Hera             Clio              Vulcan/VPS       shared-work
   nix-darwin       nix-darwin             NixOS        Home Manager
  ~/src/nix       ~/src/nix           /etc/nixos     ~/.config/home-manager
```

Four kinds of authority recur throughout the configuration:

| Authority | Meaning | Canonical example |
|---|---|---|
| Source authority | The file in which a decision is defined | `config/nix-trust.nix` owns cache and signing trust data |
| Lock authority | The checkout that selects a source revision for one consumer | Vulcan's `/etc/nixos/flake.lock` |
| Activation authority | The target-host checkout and privileged operation that may make a generation live | `make switch` on a Darwin host or `/etc/nixos/build switch` on NixOS |
| Runtime authority | Mutable state or credentials intentionally left outside the Nix store | agent sessions, authentication, service data, caches, and logs |

These authorities often cooperate, but they are not interchangeable. A source
commit does not update a consumer lock; a lock update does not build; a build
does not activate; and activation does not prove runtime health.

### Governing principles

The architecture follows a small set of rules:

1. Define shared behavior once, at the narrowest common seam.
2. Let each consumer select and activate that behavior from its own authoritative checkout.
3. Keep the portable AI boundary separately lockable, but at the same `nix-config` revision as the root source consumed beside it.
4. Keep package availability separate from host installation policy.
5. Let Nix own immutable packages and generated leaves; leave mutable application state and credentials outside Nix ownership.
6. Treat publication, consumer adoption, activation, runtime acceptance, and fleet completion as separate results.

This is a unified configuration, not a single universal flake output. The
unification lies in shared policy and implementation; the host-local locks and
activation mechanisms preserve operational control.

## 2. Repositories, clones, and authoritative checkouts

The same Git repository may have several clones. A clone's physical proximity
does not confer deployment authority. The authoritative checkout is the one
from which that host family owns its lock and activation.

### 2.1 `~/src/nix`: shared implementation and direct Darwin authority

On Hera, `/Users/johnw/src/nix` is both the implementation repository and the
authoritative checkout for Hera's direct nix-darwin output. Clio has its own
`~/src/nix` checkout, which is authoritative for Clio. The two Darwin systems
are direct outputs named `darwinConfigurations.hera` and
`darwinConfigurations.clio`.

This repository also exports the shared Home Manager module and the portable AI
subflake used by external consumers. It does not own an external consumer's
`flake.lock`, `/etc/nixos`, standalone Home Manager profile, or activation.

The repository publishes to two remotes: LAN Gitea (`origin`) and GitHub
(`github`). Both are authoritative publication destinations because different
consumers reach different remotes. `bin/publish` preflights the fast-forward
transaction without pushing; `bin/publish --publish` performs the dual-remote
publication. A push to only one remote is a partial publication.

### 2.2 `~/src/nixos`: a secondary Vulcan development clone

`/Users/johnw/src/nixos` is a useful development and inspection clone of the
Vulcan NixOS consumer. It is not Vulcan's deployment checkout. Vulcan's
authoritative source, lock, build lock, and activation surface are under
`/etc/nixos` on Vulcan.

Consequently, copying the local clone over `/etc/nixos`, activating from the
local clone, or treating a successful local evaluation as a Vulcan activation
would cross the authority boundary. Transfer reviewed commits through Git;
fast-forward the authoritative checkout; update its lock there; and run its
`./build` driver.

The Vulcan consumer imports the root `nix-config` source as a non-flake tree and
the same repository's `dir=config/ai` output as a flake. It composes those inputs
with Vulcan's own NixOS services, hardware, SOPS policy, and Home Manager
wrapper. Thus `nix-config` owns shared user and AI implementation, while the
NixOS repository owns the server operating system and service deployment.

### 2.3 `~/src/andoria`: a secondary shared-work consumer clone

`/Users/johnw/src/andoria` is a secondary clone of the shared-work consumer
repository. Its `origin` points to `andoria-08:.config/home-manager`, which makes
the direction of authority explicit: the clone follows the shared-work
checkout; it does not replace it.

The clone's `gitea` remote is the durable publication authority for reviewed
Andoria source history. The shared NFS checkout is separately authoritative for
the consumer lock and activation state. A commit may therefore be published in
Gitea without yet being adopted by the work machines, and a lock-only adoption
commit may exist in the shared checkout before it is reconciled back into the
published history. Neither state alone proves activation.

The authoritative shared-work checkout is
`/home/jwiegley/.config/home-manager`. It is shared through NFS by the four
active work machines:

1. `andoria-08`
2. `andoria-t2`
3. `delphi-3bd4`
4. `gpu-server`

The secondary clone may be used to prepare and review changes, but adoption
still occurs through Git and the authoritative shared checkout. Never copy
Hera's checkout, the secondary Andoria clone, or an arbitrary lock file over
that directory.

The Andoria consumer exports one standalone
`homeConfigurations.jwiegley` configuration for the whole policy class. It also
exports the data-only `root-policy` package described in Section 7. The
consumer repository owns these composition choices; `nix-config` supplies the
shared implementation that they select.

### 2.4 VPS and other NixOS consumers

VPS follows the same authority rule as Vulcan: the authoritative checkout is
`/etc/nixos` on the target host, and the consumer-local `./build` driver owns
build serialization and activation. `/Users/johnw/src/vps` is a secondary
authoring and review clone; it is not a substitute for the authoritative
checkout.

### 2.5 What “authoritative” does and does not mean

An authoritative checkout is not necessarily the only clone, the first clone,
or the place where an edit was composed. It is the checkout whose lock and
activation are binding for its host family. It follows that three states must be
reported separately:

- a change exists in a secondary clone;
- the authoritative checkout has adopted the commit and lock; and
- the target host has activated and accepted the resulting generation.

Only the last statement describes live deployment.

## 3. Configuration layers and ownership

The repository is organized as a pipeline from updateable source coordinates to
host-selected configuration. Each layer has one kind of decision so that an
update need not be rediscovered in several unrelated places.

```text
sources/*.json
    -> packages/source-catalog.nix
    -> packages/* and overlays/*
    -> flake/ai.nix
       |-> config/ai/flake.nix       portable AI boundary
       `-> flake.nix                 root systems and shared modules

config/ai/catalog.nix
    -> config/ai/renderers/*
    -> config/ai.nix
    -> collision-checked generated Home Manager leaves
```

### 3.1 Source catalogs

`sources/*.json` records manually tracked source coordinates, versions, hashes,
and update policy. `packages/source-catalog.nix` validates and loads that data.
Fetcher and build behavior remains in Nix derivations; the JSON records do not
become a parallel packaging language.

The updater inventory is the canonical answer to which records are automatic,
manual, or transaction-owned:

```sh
bin/update-overlay --inventory
bin/update-overlay --inventory --json
```

### 3.2 Packages and overlays

`packages/` owns reusable package sets and implementation shared by more than
one consumer. `overlays/` owns ordered exposure, narrow compatibility fixes, and
cohesive integration-specific definitions. Neither layer silently chooses a
host merely because a package is available there.

Selection belongs to the owning Home Manager, nix-darwin, or NixOS module. This
distinction prevents a portable package export from becoming an accidental
fleet-wide installation.

Watchman is intentionally absent from every rendered Home Manager package set.
The all-homes assertion preserves that absence as a package-selection invariant,
rather than retaining an unused dependency or a compatibility overlay for it.

### 3.3 Root flake and portable AI subflake

The root `flake.nix` owns the direct Darwin configurations, root packages such
as `obr`, shared Home Manager exports, host evaluation fixtures, and repository
checks. `config/ai/flake.nix` evaluates `flake/ai.nix` as a separately lockable
portable boundary containing AI packages, overlays, applications, wrappers, and
checks.

The subflake is a boundary within the same implementation tree, not a second
implementation and not a compatibility copy. External consumers can fetch
`?dir=config/ai` without evaluating Darwin-only root inputs, while the root
flake uses the same subflake locally through `path:./config/ai`.

### 3.4 Host registry

`config/hosts/registry.nix` owns stable fleet facts: platform, activation class,
login name, coarse role, shared-work membership, active rollout membership,
remote-builder records, ordered builder pools, and shell routing. The typed
surface in `config/host-options.nix` validates these records and derives
capabilities such as `isHera`, `isVulcan`, or `isSharedWork`.

Modules consume capabilities rather than scattering hostname comparisons.
Generated shell routing is a build-time projection of the same table; commands
do not invoke Nix at runtime to rediscover facts already known at evaluation.

Membership and availability are different facts. `git-ai` is a dormant
canonical shared-work member but is excluded from `activeRolloutMembers`; it is
not contacted merely because it remains in the identity table.

### 3.5 AI catalog and renderers

`config/ai/catalog.nix` owns profile identity, resource selection, audiences,
host and platform selectors, local endpoint declarations, and typed transport
policy. The files under `config/ai/renderers/` adapt that selected policy to the
native formats of Claude, Codex, Droid, Pi, Prime Agent, and the shared MCP
registry.

The catalog does not serialize client files, and renderers do not reselect
global policy. `config/ai.nix` composes the selected projections, rejects target
collisions and unsafe parent ownership, and gives Home Manager only the
generated leaves it may own.

Client-native behavior remains client-native where appropriate. Codex retains
its native model catalog; Pi discovers local models at startup; mutable auth,
history, sessions, caches, reports, and preferences remain outside generated
Nix leaves. The purpose is one policy authority, not one invented universal
client format.

### 3.6 Mutable state

Nix-owned and mutable state are separated by design:

| Nix owns | Nix does not own |
|---|---|
| Executables and package closures | Authentication tokens and secret values |
| Generated client leaves | Agent conversations, history, and sessions |
| Service definitions and immutable settings | Databases, caches, logs, and reports |
| Public trust records and host-key declarations | Private signing keys and SSH keys |
| The `obr` executable | Per-machine `.obr/` SQLite state |

Each repository's tracked `PLAN.org` is project data, while `.obr/` is an
ignored machine cache. Nix installs `obr`; it does not absorb issue state into
the store.

## 4. Revision and lock model

External consumers deliberately hold two `nix-config` inputs:

1. `nix-config`, ordinarily imported with `flake = false`, supplies the shared
   root source tree and Home Manager modules.
2. `nix-config-ai`, fetched from the same repository with `dir=config/ai`,
   supplies the portable flake outputs.

Within one consumer, both lock nodes must identify the same Git revision. A
consumer may adopt a different revision from another consumer until its own
build and activation are authorized; skew within the pair is the error.

External consumers also declare `obr` directly. The root source is imported
with `flake = false`, so its own flake inputs are not resolved; without the
direct `obr` input, the shared Home Manager module fails closed. `obr` has its
own consumer lock node and is not a third member of the paired root/AI revision
invariant.

Update the pair together, as the regular login user:

```sh
nix flake update nix-config nix-config-ai
```

Do not run `nix flake update` or `nix flake lock` under `sudo`. Root and user
fetcher caches can then disagree about local inputs and produce NAR hash
mismatches during activation. In the root repository, use:

```sh
make verify-inputs
make lock-local
```

`make verify-inputs` checks local Git inputs for skip-worktree,
assume-unchanged, submodule, and Git-link hazards before the lock is refreshed.
Never wrap a lock update in `sudo`; use the supported build or activation
driver separately, allowing that driver to acquire only the privilege its host
operation requires.

The root and portable subflakes also have their own lock files. Their shared
inputs are checked for coherence, while host-only root inputs remain outside the
portable closure. This is the cost of a separately fetchable boundary, not an
invitation to advance the two implementations independently.

## 5. Host families

Each family consumes the same shared implementation through a different
activation mechanism. The following table describes source intent, not current
reachability or deployment state.

| Family | Platform | Authoritative checkout | Output and activation model |
|---|---|---|---|
| Hera | `aarch64-darwin` | `~/src/nix` on Hera | `darwinConfigurations.hera`; nix-darwin plus Home Manager |
| Clio | `aarch64-darwin` | `~/src/nix` on Clio | `darwinConfigurations.clio`; nix-darwin plus Home Manager |
| Vulcan | `aarch64-linux` | `/etc/nixos` on Vulcan | Consumer-owned NixOS system importing shared modules |
| VPS | `x86_64-linux` | `/etc/nixos` on VPS | Consumer-owned NixOS system importing shared modules |
| Shared work | `x86_64-linux` | shared `~/.config/home-manager` | One standalone `homeConfigurations.jwiegley` that must be activated separately on four hosts |

The root flake contains generic Linux Home Manager outputs for evaluation and
smoke testing. They are not deployment shortcuts for Vulcan, VPS, or the active
shared-work hosts.

### The shared NFS home

Andoria-08, Andoria-T2, Delphi-3BD4, and GPU Server share the same home directory
and authoritative Home Manager checkout through NFS. This has two consequences.

First, every Nix-owned generated leaf must be byte-identical across the four
machines. The consumer therefore declares the logical home class
`shared-work`; a physical hostname is not a separate profile identity.

Second, a shared checkout and profile do not make machine-local Nix stores,
processes, services, or runtime state shared. The candidate closure must be
resident on every host, and the activation program must run on every host. The
configuration keeps mutable host-local state separate where necessary; for
example, shared-work shell history is named per host and shared-history merging
is disabled.

## 6. Remote builders

Remote builders are declared data, not mutable entries maintained by hand.
`config/hosts/registry.nix` owns builder identity, platform, capacity, features,
public host key, and ordered client pools. `config/darwin.nix` supplies the
host-local private-key pathname and projects the records into nix-darwin.

The declared pools are:

| Client | Ordered builders |
|---|---|
| Hera | Vulcan for `aarch64-linux`; Andoria-08 and Andoria-T2 for `x86_64-linux` |
| Clio | Hera for `aarch64-darwin`; Vulcan for `aarch64-linux`; Andoria-08 and Andoria-T2 for `x86_64-linux` |

The retired `nix-builder` virtual machine is not part of the registry. Vulcan is
the maintained ARM Linux builder. Andoria-08 and Andoria-T2 are the maintained
x86_64 Linux builders.

### `/etc/nix/machines` is generated

On Darwin, Determinate Nix owns the daemon, so the configuration uses
`nix.enable = false` and explicitly serializes `nix.buildMachines` into
`/etc/nix/machines`. A nix-darwin activation compares the candidate file with
the current generation; when the bytes differ, it restarts the Determinate
daemon and waits through bounded readiness probes.

Never edit `/etc/nix/machines` directly. Such an edit has no source authority,
will be replaced by activation, and makes the live state impossible to explain.
Change the registry or its projection, build the Darwin system, inspect the
generated file, and activate the owning host.

Clio reaches the Andoria builders through Hera. Its generated SSH fragment uses
a pinned jump-host key and strict host-key checking. Hera does not receive that
proxy fragment because it reaches the builders directly.

### Builder transport and privilege

The Andoria rows use plain `ssh-ng` as the unprivileged `jwiegley` account.
Builder transport does not grant daemon trust, and it does not require a remote
program that invokes `sudo`. The remote daemon accepts imported store paths
according to the signing policy in Section 7.

Four authorities remain separate:

- SSH authentication permits a connection;
- Nix signatures permit store-path import;
- `sudo` permits a human administrative operation; and
- an authorized root installation and daemon restart changes daemon policy.

Conflating these would turn a narrow build route into general root access.

### Capacity limits

The shared-work Home Manager configuration renders the following unprivileged
client policy:

```text
max-jobs = 1
cores = 8
```

For a shared-work client, `max-jobs = 1` requests one local build job and
`cores = 8` supplies an eight-core hint to that job. Each Andoria builder row
separately declares `maxJobs = 1`; this is a per-client scheduler limit for that
row, not a pool-wide ceiling across unrelated clients. Darwin Home Manager also
exports `NIX_CONFIG = "cores = 8"`, so Darwin-dispatched work carries the same
core request. The Darwin daemon defaults remain distinct: Hera and Clio declare
eight and four local jobs respectively, with ten cores.

All of these settings are cooperative Nix and build-system inputs. They are not
an operating-system cgroup, and a derivation may disregard the core hint. The
shared-work registry therefore also declares `nixDaemonAllowedCpus = "0-7"`.
The authoritative Andoria consumer renders it in the separate
`nix-daemon-cpu-policy` output as `AllowedCPUs=0-7` for `nix-daemon.service`.
The daemon and every process in its cgroup can execute only on those eight
logical CPUs on each active shared-work host, without changing that host's cache
or signature trust policy.

Do not generalize the statement to every build surface. Darwin daemon defaults,
focused package-build modes, and remote builder capacities have their own
declared settings. Pass `--max-jobs 1 --cores 8` explicitly when the generated
client policy is not yet active, but treat those values only as cooperative
hints. Do not start a resource-intensive shared-work build until the root-owned
CPU set is active.

The executable installation and verification procedure has one owner:
`root-policy/README.md` in the authoritative Andoria checkout. It retains the
predecessor before replacement, installs the rendered leaf, reloads and restarts
the daemon, verifies the file and active cgroup, and restores the predecessor on
any failure. It then forces a fresh, local, unsubstituted derivation whose own
`/proc/self/status` must report `Cpus_allowed_list: 0-7`. Run that procedure
separately on every active shared-work host after quiescing its Nix builds. A
Home Manager switch neither installs nor rolls back this root-owned file.

## 7. The Andoria Determinate Nix trust leaf

The `root-policy` output is a small data projection, not a configuration or
lifecycle framework. It renders public trust data for the Ubuntu/Determinate Nix
daemons on the two Andoria builders while Home Manager remains strictly
user-scoped. The output neither installs itself nor governs another host's root
Nix configuration.

### 7.1 Source authority

`config/nix-trust.nix` owns the shared trust record. Its `determinateLinux`
value declares:

- `requireSigs = true`;
- `trustedUsers = [ "root" ]`;
- `extraSubstituters` for the approved caches; and
- `extraTrustedPublicKeys` for those caches and the authorized client signer.

The Andoria consumer imports that value and renders one store output whose leaf
is `etc/nix/nix.custom.conf`. Its documented operator procedure applies the leaf
separately to each Andoria builder. Another shared-work host may use the common
trust data only through its own root authority; this output's existence does not
establish installation there. The renderer performs no host discovery and
contains no secret. It serializes the camel-case source fields as the dashed Nix
settings
`require-sigs`, `trusted-users`, `extra-substituters`, and
`extra-trusted-public-keys`.

Home Manager writes the unprivileged client policy under
`~/.config/nix/nix.conf`, including scheduler bounds, experimental features,
and cache requests. A user configuration can request a substituter, but it
cannot make the root daemon trust that substituter or its signatures. That is
why the root-owned leaf exists.

### 7.2 Installation authority

An authorized operator, not Home Manager, installs the rendered leaf. Before
replacement, retain the exact previous root-owned leaf or its producing store
path through the host's approved rollback practice. Then, from the
authoritative Andoria checkout, apply the fail-closed procedure:

```sh
(
  set -euo pipefail
  policy="$(nix build --no-link --print-out-paths .#root-policy)"
  candidate="$policy/etc/nix/nix.custom.conf"
  test -f "$candidate"
  sudo install -o root -g root -m 0644 \
    "$candidate" /etc/nix/nix.custom.conf
  sudo cmp "$candidate" /etc/nix/nix.custom.conf
  sudo systemctl restart nix-daemon.service
  systemctl is-active --quiet nix-daemon.service
)
```

This is a separately authorized root operation. A Home Manager switch does not
perform it; a source commit does not prove it occurred; and the presence of a
`root-policy` output in a secondary clone does not prove authoritative adoption.

Should the new daemon policy fail acceptance, restore the retained exact leaf,
restart the daemon, and repeat the byte comparison and behavioral checks.
Direct installation has no implicit NixOS generation rollback.

### 7.3 Acceptance

File equality and daemon activity are necessary but incomplete. Repeat the
acceptance for each Ubuntu/Determinate daemon receiving the leaf. From an
authorized signing client, create fresh equivalent ordinary store paths and
prove both sides of the trust boundary:

1. a path carrying the authorized Nix signature imports successfully; and
2. the otherwise equivalent unsigned path is rejected.

Inspect the effective daemon configuration as structural fields, without
printing private key material. The positive test proves utility; the negative
test proves that `require-sigs` is not merely present in source.

### 7.4 What the root policy does not do

The root policy does not grant or remove human `sudo`; add `jwiegley` to
`trusted-users`; install a private signing key; authorize SSH; select a remote
builder; or activate Home Manager. Human administration remains an ordinary
host policy. This separation is the reason the mechanism can remain small.

## 8. Signing and publication

Two independent signature systems appear in this configuration.

### Git commit signatures

Repository policy requires every new commit to be signed. The pre-push gate
verifies every commit that would become newly visible on either publication
remote, not merely the tip. Stage explicit paths, inspect the index, and do not
bypass hooks.

`bin/publish` then verifies a clean tracked tree, refreshes both remote views,
checks fast-forward ancestry and signatures, performs dry-run pushes, runs the
tracked pre-push gate once, publishes, and reads both remote refs back. It never
force-pushes. Since two remotes cannot form an atomic Git transaction, a partial
publication is reported as a failure requiring reconciliation.

The bare command is inspection only; publication is explicit:

```sh
bin/publish             # Preflight only; pushes nothing.
bin/publish --publish   # Run the gate and publish to both remotes.
```

### Nix store signatures

A Nix store signature attests a realized NAR; it is not a Git signature. The
authorized Darwin clients reference a private Nix signing key outside the
repository, while `config/nix-trust.nix` contains only its public identity. The
private key contents must never enter Git, a derivation, generated
configuration, a command argument, or diagnostic output. A configured key-file
pathname is not itself secret material.

When a shared-work candidate contains locally built paths, sign the required
closure from an authorized client before copying it into a daemon that enforces
`require-sigs`. Verify the signatures and the exact candidate path before
activation. Trusting the public key permits path import; it does not confer
shell or root authority on the signer.

## 9. Development, update, and closeout workflow

The ordinary workflow moves from a narrow source change to broader evidence.
It begins in the owning checkout, not in generated state.

### 9.1 Begin work

```sh
cd ~/src/nix
direnv allow       # only when the reviewed .envrc requires first-time approval
obr ready
obr show ISSUE-ID
obr update ISSUE-ID --status=in_progress
git status --short --branch
```

Use the existing direnv environment for all repository commands. Do not use
`nix develop` for agent work and do not install missing tools ad hoc; add the
tool to the declared environment, regenerate it with `de`, and reload direnv.

Preserve every unrelated working-tree change. Do not use `reset`, `restore`,
`clean`, or `stash` as a convenience for obtaining a clean view. Where a
transaction requires a clean checkout, commit the owner's intended work or use
a separate reviewed checkout; never erase it.

### 9.2 Make the change at one authority

Change the source catalog for source coordinates, a package for reusable
implementation, an overlay for ordered exposure or a narrow compatibility fix,
the AI catalog for profile/resource selection, a renderer for client
serialization, the host registry for fleet facts, and the consumer repository
for consumer-specific composition.

Search maintained consumers before removing a compatibility route. Generated
files are projections, not independent policy.

### 9.3 Verify in increasing scope

Useful focused and bounded commands include:

```sh
test/bin/unittest-strict.py test/bin/update-overlay-slow-test.py
nix flake check ./config/ai --all-systems --no-build
make test
./build pkg PACKAGE
./build system
lefthook run pre-commit --all-files
```

Run the expensive tier at issue closeout or on its scheduled cadence, after
focused verification and required activations no longer depend on immediate
progress:

```sh
make expensive
```

The expensive tier complements the ordinary pre-commit gate; it does not
replace formatting and static checks.

### 9.4 Commit and record issue state

Update the claimed `obr` issue, write its tracked projection, then stage only
the intended code and `doc/PLAN.org`:

```sh
obr close ISSUE-ID --reason="Completed"
obr sync --flush-only
git status
git add -- path/to/code doc/PLAN.org
git diff --cached --check
git commit -S
```

Nothing under `.obr/` is committed. The issue transition and the code that
satisfies it belong in the same logical signed commit.

### 9.5 `make update`

From the authoritative root repository, the canonical automatic update is:

This command performs both activation and publication. Obtain explicit
authorization for each action before invoking it.

```sh
make update
```

It delegates to:

```sh
bin/update --all-inputs --pull --commit --switch --push
```

This is a root-repository transaction: it requires a clean checkout, takes a
repository lock, constructs an isolated candidate, updates both flake locks and
automatic source records, rejects undeclared mutations, validates, creates a
signed commit, activates the exact candidate on the current supported host,
fast-forwards the branch, and publishes through `bin/publish`. Homebrew remains
outside the transaction.

Automatic catalog targets run serially, each with its own pre-target Git tree
and untracked-path snapshot. The updater treats its recognized
candidate-rejection status as provisional: it restores the exact staged Git
tree, verifies that the untracked and ignored path set is unchanged, and thereby
restores the tracked source record, dependent hashes, generated locks, and
flake-lock projections. It then validates the restored target through its
declared package and build mode. Only a successful restored-baseline validation
permits the updater to report the retained version and continue with later
targets against the accepted on-disk state.

A raw Nix status of 3, command or process-launch failure, signal, timeout,
restore mismatch, undeclared mutation, failed baseline, or final repository
validation failure remains fatal. One explicitly selected rejection, or an
aggregate in which every selected target is held back, exits nonzero. This
distinction keeps one bad package update from suppressing unrelated good updates
without concealing a broken updater or an operational failure.

`make update` is not a whole-fleet deployment. It neither updates every external
consumer lock nor proves closure residency, activation, and runtime behavior on
every host.

## 10. Activation procedures

Activation is always target-owned and separately authorized. Before switching,
record the exact source revision, consumer lock, candidate output, and previous
generation needed for rollback.

### 10.1 Hera and Clio

Run from the target host's authoritative `~/src/nix` checkout:

```sh
(
  set -euo pipefail
  make verify-inputs
  make build
  make switch
)
```

`make build` realizes the complete Darwin system without activating it.
`make switch` refreshes local-file inputs through `lock-local`, invokes
nix-darwin, and activates the selected generation. Because that lock refresh
occurs after the preliminary build, `make build` does not prove that the later
switch selects the same closure; the switch and active-system readback are the
evidence for the activated candidate. Clio must first fast-forward its own
checkout to the reviewed published revision.

After activation, verify the active `/run/current-system`, the generated
`/etc/nix/machines` link and bytes when builder policy changed, Determinate
daemon readiness, and the affected client or service. A successful switch alone
does not establish those runtime results.

### 10.2 Vulcan and VPS

Run lock updates as the regular user from the target's authoritative
`/etc/nixos`, keeping `nix-config` and `nix-config-ai` paired. Build and switch
through the consumer's driver:

```sh
(
  set -euo pipefail
  cd /etc/nixos
  nix flake update nix-config nix-config-ai
  ./build build
  ./build switch
)
```

The driver coordinates work through `/etc/nixos/.nixos-build`, records a
bounded root-only log, and releases its own lock on success, failure, or signal.
It waits up to four hours by default, reclaims a provably stale recorded holder
early, and forcibly seizes the lock at the timeout even when the holder is live
or unknown. It is therefore not a strict exclusion guarantee for a build that
can exceed that bound; do not start a competing invocation, and choose an
appropriate wait bound deliberately. Raw `nixos-rebuild` bypasses the driver
contract and is not the supported operator path.

Verify the active NixOS generation, relevant systemd units, Home Manager user
generation, and affected runtime behavior. SOPS decryption and service data are
consumer-owned concerns and must not be inferred from a root-repository build.

### 10.3 The four shared-work hosts

The shared-work rollout is one candidate applied to four local stores and four
host runtimes. The canonical order is fixed:

1. `andoria-08`
2. `andoria-t2`
3. `delphi-3bd4`
4. `gpu-server`

Update the paired inputs once from the authoritative shared checkout:

```sh
(
  set -euo pipefail
  cd /home/jwiegley/.config/home-manager
  nix flake update nix-config nix-config-ai
)
```

Review the lock change and record it in a signed consumer-adoption commit under
the repository's issue workflow. Confirm that the resulting authoritative
checkout is clean. Then prepare the fleet candidate from that exact commit:

```sh
(
  set -euo pipefail
  cd /home/jwiegley/.config/home-manager
  nix flake check --no-build --no-update-lock-file
  candidate="$(nix build --builders "" --max-jobs 1 --cores 8 \
    --no-link --print-out-paths \
    '.#homeConfigurations."jwiegley".activationPackage')"
  printf 'candidate=%s\n' "$candidate"
)
```

This preflight evaluates the consumer's declared checks without realizing the
broad check closure. The activation package is then built completely as the
single fleet candidate. Realize the broad check set only at final closeout,
after the required activations and focused runtime acceptance are complete.

The designated producer may differ when operational capacity requires it; the
identity of `candidate` must not. Once realized, perform the following barrier
before the first activation:

1. Confirm the paired input revisions and clean authoritative checkout.
2. Record the exact candidate and its recursive closure.
3. Retain the previous activation closure on every target and retain the
   candidate on its producer.
4. If locally built paths require the client trust root, bring the closure to an
   authorized signing client, sign it recursively, and verify the signatures.
5. Copy the exact signed closure to all four hosts.
6. Retain the candidate against garbage collection on each target.
7. Prove closure residency on every host without rebuilding or reevaluating it.

Only after that barrier, run the same activation program serially on the four
hosts in the order above. Until the newly generated client configuration is
known active, retain the explicit scheduler bound:

```sh
NIX_CONFIG=$'builders =\nmax-jobs = 1\ncores = 8' \
  "<exact-candidate-store-path>/activate"
```

Stop on the first failure. Do not let a successful Andoria-08 activation become
permission to skip closure or runtime proof on the remaining machines. On each
host verify the selected Home Manager generation, local closure residency,
rendered `max-jobs = 1` and `cores = 8`, and the affected command or service.

The `switch` helper can build and activate the pinned `jwiegley` output on one
shared-work host. The legacy `update-remote` command updates once and invokes
that helper sequentially. Neither command, by itself, realizes once, proves
four-host closure residency, or retains rollback roots; neither therefore
constitutes fleet proof.

### 10.4 Root-policy installation and acceptance

Apply the selected trust leaf separately on each affected Andoria builder before
depending upon that daemon to accept client-signed closures. Trust-leaf
installation and Home Manager activation are separate operations. Complete the
signed-positive and unsigned-negative acceptance described in Section 7 before
using either builder as evidence for the trusted copy path.

## 11. Rollback and recovery

Rollback begins before activation by retaining an exact previous state. It is
not a repair invented after a failure.

### 11.1 Source and publication recovery

Published history is not rewritten as routine recovery. Correct a published
source error with a new signed commit. `bin/publish` refuses force options; a
partial two-remote publication must be reconciled explicitly and read back
before consumers adopt it.

If `bin/update` rejects one package candidate, inspect its report and retained
version. Do not use a broad reset or stash to “clean up” the checkout. Hard
transaction failures may have completed external effects; the transaction
reports them rather than pretending atomicity across activation and two Git
remotes.

### 11.2 Consumer lock rollback

Select a previously accepted root revision in the consumer and keep the root
and `dir=config/ai` inputs paired. Build the resulting consumer before switching.
Do not roll back only one of the two nodes, and do not copy a lock from another
host family merely because it names the desired revision.

### 11.3 Darwin and NixOS generation rollback

Retain the previous nix-darwin or NixOS generation until runtime acceptance is
complete. Use the target host's native generation mechanism and authoritative
checkout to reactivate it, then repeat runtime checks. On NixOS, preserve the
consumer build lock by going through `/etc/nixos/build`; do not start a competing
raw rebuild.

### 11.4 Shared-work rollback

Retain the previous activation package and its closure in every one of the four
stores before the first switch. Because the profile is shared while stores and
host-local effects are not, a partial rollout requires inspection of every host,
not merely the host on which the command failed.

If acceptance fails, stop the rollout; identify which hosts ran the activation;
activate the exact retained previous package wherever the shared profile or
host-local state changed; and verify all four machines again. Do not expire a
shared generation while any host may still need it.

### 11.5 Andoria trust-leaf rollback

Restore the exact previously accepted `/etc/nix/nix.custom.conf`, restart
`nix-daemon.service`, compare the bytes, inspect effective non-secret fields,
and repeat signed-positive and unsigned-negative probes on every affected
builder. A daemon that merely starts has not yet proved the old trust boundary
restored.

## 12. Security boundaries

Security in this repository rests principally on keeping immutable policy,
privileged activation, and mutable secrets in their proper domains.

### 12.1 Secrets never enter the store

Nix store paths are not a secret store. Any secret referenced during evaluation
or embedded in a derivation may become readable through the store, logs, or
substitution. Pi and Codex credentials therefore remain environment references;
request-time values never enter argv, generated files, or derivations.

Do not decrypt or print SOPS content, runtime secret files, Keychain values,
private signing keys, API payloads, or credential-bearing settings for
diagnostics. Prefer field-targeted structural checks. The NixOS consumers own
their SOPS lifecycle; Darwin services use their declared Keychain or protected
runtime boundaries.

### 12.2 Public policy is not private material

Cache public keys, Nix client-signing public keys, and SSH host public keys are
appropriate declarative inputs. Private SSH identities and the Nix signing key
remain host-local. The host registry names logical identities; the Darwin module
maps them to local paths without importing their contents.

### 12.3 Least privilege across transport boundaries

Pinned SSH host keys authenticate the builder endpoint. Plain unprivileged
`ssh-ng` carries the build protocol. The root daemon verifies store signatures.
Human `sudo` remains independent. No one of these controls substitutes for the
others.

### 12.4 Generated configuration and mutable parents

Home Manager owns generated leaf files, not whole mutable application roots.
The AI composer checks for target collisions, unsafe relative paths, ancestor
ownership, and mutable MCP adapter paths before activation. This permits Nix to
enforce immutable policy without erasing sessions, preferences, caches, or
auth state.

### 12.5 Network allowlists

Service access policy belongs in the owning declarative module. For example,
Hera's oMLX TLS proxy and its admitted source addresses are declared in
`config/darwin.nix`; a hand-edited Nginx file has no lasting authority. Change
the source allowlist, build and activate Hera, then perform a credential-safe
runtime request from the admitted client. Source presence alone does not prove
that Nginx loaded the new generation.

### 12.6 Operational safeguards

- Preserve unrelated working-tree changes, local commits, lock updates, tmux
  sessions, and mutable agent state.
- Stage explicit paths and inspect the index before every signed commit.
- Keep publication, activation, destructive cleanup, and history rewrite
  independently authorized.
- Never edit Nix store paths, generated profile links, or `/etc/nix/machines`
  directly.
- Avoid concurrent builds or activations against one authoritative checkout or
  shared profile.
- Retain rollback generations until runtime acceptance, not merely until switch
  exit zero.

## 13. Evidence and completion

Evidence labels state exactly what ran. They prevent a local or partial success
from becoming an unsupported fleet claim.

| Evidence | Establishes | Does not establish |
|---|---|---|
| Source review | The declared policy has the intended shape | Evaluation, deployment, or live state |
| Evaluation | Nix can construct the configuration | Derivation success |
| Build | The selected closure can be realized | Activation anywhere |
| Closure residency | One target has the exact closure locally | Profile selection or runtime health |
| Activation | One host selected or ran the new generation | Client or service behavior |
| Publication | Both Git remotes contain the signed revision | Consumer lock adoption |
| Runtime acceptance | The affected executable, service, or security boundary works on one active host | Health on another host |
| Fleet acceptance | Every named target completed the required build, activation, and runtime checks | Future availability |

A four-host shared-work change is complete only when all four active targets
have the exact candidate closure, the activation has run in the prescribed
order, and each host has passed the relevant runtime checks. A builder change
additionally requires a fresh build through the exact generated route. A trust
change requires signed acceptance and unsigned rejection on every affected
daemon.

Record hashes, revisions, output paths, host names, and commands with the issue
evidence. Do not call focused checks “all tests,” a source declaration “live,”
or membership “availability.”

## 14. Troubleshooting by boundary

When a change fails, identify the boundary before changing code.

### A package update is rejected

Read the per-target `bin/update` report. A recognized candidate rejection retains
that package's prior version and permits later automatic targets to run only
after restoration of the exact staged Git tree, verification of the unchanged
untracked and ignored path set, and successful validation of the restored
baseline. A raw Nix status of 3, persistent baseline failure, updater or
process-launch error, signal, timeout, undeclared mutation, or restore mismatch
is a transaction failure and must not be reclassified as a package rejection. A
single explicitly selected rejection, and an all-held-back aggregate, both
return nonzero.

### A remote builder is missing or unreachable

Compare `config/hosts/registry.nix`, the nix-darwin evaluation, the candidate
`etc/nix/machines`, and the live `/etc/nix/machines` in that order. If source and
candidate agree but live bytes differ, the problem is adoption or activation.
Do not repair the live file by hand. Separately verify SSH reachability, pinned
host keys, signing trust, platform selection, and daemon health.

### A signed path is rejected

Check the effective daemon fields, the installed leaf's equality to the selected
`root-policy` output, daemon restart status, the path's actual signatures, and
the public-key identity. Do not weaken `require-sigs`, add the login user to
`trusted-users`, or replace plain `ssh-ng` with remote `sudo` merely to make the
probe pass.

### A Home Manager build succeeds on only one shared host

Treat the result as one-host build evidence. Check whether the exact closure is
resident in every local store, whether trust accepts its locally built paths,
and whether the old generation is retained. Do not reevaluate four candidates
from the shared checkout and call them one rollout.

### Activation exits successfully but the feature is absent

Verify the active generation, then inspect the actual service or client. For a
daemon-backed change, confirm that the daemon reloaded the generated file. For
an allowlist change, test from the intended source address. For a command,
resolve and run the binary from the active profile. Activation is a transition,
not runtime acceptance.

### A lock update produces a local-input NAR mismatch

Stop using root-owned lock commands. Return to the regular user, run
`make verify-inputs`, repair the reported Git-index or submodule condition, then
run `make lock-local`. Do not copy another host's lock as a shortcut.

## 15. Current work and documentation

Use `obr` for all current work:

```sh
obr ready
obr show ISSUE-ID
obr update ISSUE-ID --status=in_progress
obr close ISSUE-ID --reason="Completed"
obr sync --flush-only
obr sync --status
```

`doc/PLAN.org` is the tracked projection and review trail. `.obr/` is a
per-machine cache and is never committed. Git history preserves completed
execution history; architecture documents describe the present design.

The documentation set has distinct purposes:

| Document | Purpose |
|---|---|
| `README.md` | Repository entry point and concise ownership map |
| `doc/ARCHITECTURE.md` | Normative data-flow and ownership contract |
| `doc/USER-GUIDE.md` | Operator explanation and procedures represented by this guide |
| `bin/README.md` | Exact command inventory and command-specific cautions |
| `test/README.md` | Verification scope and maintainability policy |
| `doc/SECURITY.md` | Source-backed security ledger requiring live verification |
| `doc/PLAN.org` | Sole current-work authority through `obr` |

No document in this table replaces another. In particular, the user guide
explains how the system works but never records the current issue roster or a
transient deployment checkpoint.

## 16. Operator checklists

### Root implementation change

1. Claim the `obr` issue and inspect the clean/dirty state without altering unrelated work.
2. Change the narrowest owning source.
3. Run focused checks, the bounded repository gate, and the affected build.
4. Close or update the issue and flush `doc/PLAN.org`.
5. Stage explicit paths and create a signed commit.
6. Run independent review and the pre-push signature gate.
7. Publish fast-forward-only to both remotes.
8. Let each affected consumer adopt the paired revision from its authoritative checkout.
9. Build, activate, and perform runtime acceptance per host family.
10. Run low-frequency expensive assurance at closeout, after other required verification and activation are complete.

### External consumer adoption

1. Enter the target family's authoritative checkout.
2. Preserve local commits, dirty state, and host-specific lock changes.
3. Update `nix-config` and `nix-config-ai` together as the regular user.
4. Verify the two locked revisions are equal.
5. Evaluate and build through the consumer's supported driver.
6. Retain the prior generation or activation closure.
7. Activate only with explicit authorization.
8. Verify the active generation and affected runtime behavior.

### Four-host shared-work rollout

1. Update and check the shared authoritative checkout once.
2. Realize one bounded candidate.
3. Sign locally built closure paths through the authorized trust root.
4. Prove exact closure residency and rollback retention on all four hosts.
5. Activate Andoria-08.
6. Activate Andoria-T2.
7. Activate Delphi-3BD4.
8. Activate GPU Server.
9. Verify generation, scheduler policy, and affected runtime on every host.
10. Retire rollback roots only after fleet acceptance.

The configuration remains comprehensible when every operation answers four
questions: which source owns the decision, which checkout selected it, which
host activated it, and what runtime evidence followed. Everything else is a
projection of those answers.
