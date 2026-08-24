# Architecture

## Purpose

This repository owns shared Nix configuration and package implementation for two
Darwin systems, external Home Manager and NixOS consumers, and a portable AI
toolchain. One implementation revision serves every consumer; each consumer keeps
its own lock and activation authority.

## Configuration flows

### Darwin

```text
flake.nix
  -> darwinConfigurations.{hera,clio}
  -> config/darwin.nix
  -> Home Manager config/home.nix
  -> config/johnw.nix + config/packages.nix
  -> config/ai.nix
```

Hera and Clio are direct root-flake outputs. Only the authoritative checkout on
the target host may activate them.

### Portable AI

```text
config/ai/flake.nix
  -> flake/ai.nix
  -> overlays/ai/default.nix
  -> packages + checks + apps
```

`config/ai` is a separately lockable, remote-fetchable boundary over the same
implementation tree. The root and portable locks must agree on shared inputs;
host-only inputs stay outside the portable closure.

The former root `flake-ai.nix` shim and later legacy subflake-path stub were
retired after authoritative consumer evaluation and code search found no
maintained import. Portable consumers use `flake/ai.nix` through `config/ai`.

### External consumers

The supported shape is a paired root source and `dir=config/ai` input at one
revision. Cleanup issue #114 verified the paired-revision mechanism on the
then-canonical path in the authoritative shared-work, VPS, and Vulcan checkouts;
issue #126 completed the cutover to `config/ai`. The source has no compatibility
route at the retired path.

External Home Manager and NixOS checkouts own their locks and activation. This
repository exports implementation and modules; it does not overwrite another
consumer's checkout or deployment state.

VPS remains a supported external consumer but is parked outside the default
cross-consumer evaluation and active rollout sets. Its explicit consumer
evaluation and consumer-owned build driver remain available for deliberate
future updates.

## Host registry and shared-home policy

`config/hosts/registry.nix` is the data authority for host system, activation,
login, the lean-server role, shared-work membership, rollout targets, daemon and
local-build capacity, distributed-builder identity and client pools, and shell
host/output routing. `config/host-options.nix` gives the host tables a typed module surface
and derives the capability flags consumed by modules. Darwin projects each
builder's named SSH identity to its host-local key path and writes the resulting
ordered pool to `/etc/nix/machines`; the registry does not own private key
material.

The four active shared-work machines use one generated Home Manager
configuration. Their Nix-owned leaves must therefore remain byte-identical.
Dormant `git-ai` is also a canonical member of that policy class, but membership
does not claim present availability and does not add it to the explicit active
rollout. The registry classifies the shared home; each owning module remains
responsible for separating any per-machine mutable state from shared generated
leaves.

The shared-work registry also declares the CPU set available to each system Nix
daemon. The external Andoria consumer renders that value as an ordinary
systemd drop-in in a data-only output separate from the Andoria trust policy.
The operating-system cgroup is the hard boundary; Home Manager's `max-jobs` and
`cores` values remain useful client scheduling hints but cannot enforce a
machine-wide ceiling.

`config/hosts/shell-routing.nix` renders the shell normalization, flake-output,
membership, and active-rollout projection from the registry. `nix-scripts`
installs that rendered file at package build time. The source-tree copy is a
generated convenience for direct repository commands and must remain byte-equal
to the renderer; shell commands never invoke Nix to rediscover routing at runtime.

For the explicit four-host shared-work rollout:

1. realize the candidate once;
2. copy and prove the closure is resident on every target;
3. retain a GC root for the previous closure; and
4. activate each host from its authoritative checkout.

Do not expire generations through a shared profile while another host may still
need them for rollback.

## Ownership

| Path | Owns | Must not own |
| --- | --- | --- |
| `config/hosts/registry.nix` | Host identity, capabilities, membership, rollout selection, daemon, local-build, and distributed-builder capacity, builder pools, and routing data | Module or shell implementation, private SSH key material, or activation |
| `config/hosts/shell-routing.nix` | Build-time shell projection of registry routing data | Independent host identity policy or runtime Nix discovery |
| `config/nix-trust.nix` | Shared binary-cache and client-signing trust data | Root-file installation or host activation |
| `config/ai/catalog.nix` | Profiles, selectors, resources, validation | Client serialization or package builds |
| `config/ai/renderers/*` | Generated documents for one client | Global resource selection |
| `config/ai.nix` | Home Manager composition and ownership guards | Package implementation |
| `flake/ai.nix` | Portable package, app, and check composition | Host activation or root lock policy |
| `packages/*` | Reusable package sets and multi-consumer build/runtime implementation | Host selection |
| `overlays/*` | Ordered exposure, compatibility fixes, and cohesive integration-owned package definitions | Hidden host selection or unrelated configuration channels |
| `test/*` | Interface and integration contracts | Duplicate production algorithms |
| `bin/*` | Operator transactions | Implicit cross-repository mutation |

The shared-work Home Manager leaf requests the declared caches for unprivileged
Nix clients; it cannot authorize those caches in the system daemon. Ubuntu
Determinate Nix hosts render `determinateLinux` into the root-owned
`/etc/nix/nix.custom.conf` through their consumer configuration. The same
consumer renders the independent shared-work CPU set into a systemd drop-in.
An authorized operator installs the applicable leaf and restarts the daemon.
The trust policy keeps `require-sigs = true` and `trusted-users = root`; Home
Manager never writes the root-owned files or makes the login user a trusted Nix
user.

## AI configuration

```text
llm-setup-models-list -> llama-swap configuration and GPTel
oMLX /v1/models -------\
                         -> Pi startup and /model discovery
llama-swap /v1/models --/

Nix client-local transport/default/override policy
  -> renderer adapters
  -> collision-checked generated leaves
  -> Home Manager preflight and activation
```

Nix owns endpoint wiring and client-specific policy, not a cross-client model
inventory. Codex retains its native catalog. Pi renders its cached model snapshot
immediately, gives `/model` refreshes the upstream 15-second selector deadline,
and discovers local models at startup and through its native provider-refresh contract.
Droid receives no Nix-generated local-model list, and Prime Agent reuses the safe
Pi-compatible model overrides plus the shared local-provider discovery packages.
The catalog declares host-local inference endpoints once per catalog host for
fixed routes and non-Pi consumers. Darwin Pi receives a separate bilateral
discovery map: local llama-swap plus the stable `omlx-clio` and `omlx-hera`
providers. Both Pi homes therefore render the same provider identities while
retaining their host-specific fixed-route policy.

oMLX itself is loopback-only. Its TLS gateway route is absent by default; both
Darwin workstations enable it on their exact LAN address and admit the other
workstation, with Hera retaining its declared gateway sources. Nix supplies the
reviewed, CA-signed server leaf for each listener and trusts only the existing
root CA; each matching private key remains a mode-0600 host-local file. Pi
resolves two provider-specific environment names at process start, preferring
explicit values and login-Keychain items before the services' non-secret
compatibility sentinel. The generated provider records contain only those
environment references. Nginx forwards each bearer header unchanged, and
the destination oMLX instance validates its own credential. This keeps one
authentication authority instead of consuming the OpenAI `Authorization` header
in a second Basic-auth layer.

The initial Prime Agent profile is Hera-only. Its prompt commands and Agent Skills
are direct catalog projections; static specialist definitions become native RLM
prompt adapters; stdio MCP remains available through the shared `pi-mcp-adapter`
because Prime Agent's native MCP integration accepts HTTP transports only. Pi and
Prime consume one catalog-selected registry below `XDG_CONFIG_HOME`; its shared
projection emits that leaf once and guards each mutable adapter root from shadowing it.

Pi's managed local providers carry their long request and stream-idle budgets as
typed `transport` data in `models.json`. The runtime turns that capability into
provider-scoped client options; the ordinary global HTTP timeout remains unchanged.

Prime Agent is built from the reviewed source revision and normalized dependency
lock. Nix owns a separate, highest-precedence `managed-settings.json` leaf binding
the package, theme, and extension roots. Upstream's ordinary `settings.json` remains
a mutable regular file for onboarding, default/recent models, and user preferences;
preference writes cannot alter or displace the managed overlay. The wrapper binds
Prime Agent and inherited Pi-compatible adapters to one Prime-private root and
propagates it to daemon/RLM children. Credentials remain environment references;
secret values never enter derivations, generated files, or argv. Auth, history,
sessions, daemon and kernel state, continual-harness refinements, caches, reports,
and trust state remain mutable.

Package availability is separate from installation policy. Reusable package sets
live under `packages/`. A cohesive package can be defined in its owning overlay
when that is the narrowest integration boundary; overlays also expose packages and
apply compatibility fixes. Owning host or feature modules select packages
explicitly.

`obr` is not part of the portable AI boundary. The root flake owns its input and
package export, and `config/obr.nix` selects it for every managed home. Nix owns
the executable, while each machine owns its ignored `.obr/` cache and each
repository owns its tracked `PLAN.org` issue surface. A consumer that imports
this repository as a non-flake source must declare `obr` directly and pass it in
the Home Manager module arguments. That explicit consumer lock is part of the
separately authorized adoption step; the module fails closed when it is absent.

Pi uses the floating `llm-agents` packaging substrate while replacing its built
artifacts with the reviewed source build in `packages/pi-source-build.nix`
(record `pi-coding-agent-source-build` in `sources/ai.json`). `flake/ai.nix`
asserts that the feed package and reviewed source build have the same version,
so an automatic feed advance fails at evaluation until the source, downstream
patches, and Gallery compatibility surface are reviewed together. The
`llm-agents-nixpkgs-independent` check keeps the feed's nixpkgs input independent
from the consumer channel.

Pi gallery normalization has one implementation:
`packages/pi-gallery/normalization-policy.json` defines the closed policy and
`packages/pi-gallery/normalize-manifest.jq` executes it for both builds and updates.
The full package projection remains uniform across hosts, while Pi Lens and Pi Mem
are presently excluded from the generated active order so their startup costs can
be isolated without uninstalling them.
The Darwin gallery performs bounded loopback model discovery on both
workstations, while `config/ai/catalog.nix` grants fixed local-provider overrides
only to profiles whose exact model inventory has been verified. These overrides
are not a second inventory: endpoint availability and discovered inventory are
distinct authorities. Pi-Bifrost routing policy remains mutable project state.

## Source and update authority

`sources/*.json` owns updateable source coordinates, versions, and dependent
hashes. Native Nix derivations retain fetcher and build logic and load records
through `packages/source-catalog.nix`. Generated npm, Cargo, and flake locks remain
updater-owned projections beside their consumers.

`bin/update` performs the isolated repository update transaction. `make update`
requests the complete pull, update, validation, signed commit, exact-candidate
build and activation, publication, and push sequence. It streams one dot per
work item, then reports accepted old-to-new catalog changes only after every
requested action and transaction cleanup succeeds. `make update-verbose`
exposes detailed progress and successful no-op diagnostics. Homebrew is outside
the repository transaction.

Routine validation should use scoped outputs. Broad root checks can force unrelated
host-only inputs; the portable subflake exists so remote-safe checks can evaluate
the portable closure without them.

## Publication and activation

The repository has one authoritative remote: LAN Gitea, named `origin`, at
`gitea@gitea:johnw/nix-config.git`. It is the sole fetch and push authority;
GitHub must not be configured as a remote. Managed consumers may fetch the same
repository through the exact public HTTPS fetch endpoint at
`https://gitea.newartisans.com/johnw/nix-config.git`. `bin/publish` verifies the
configured SSH fetch and push URLs, then owns
the fast-forward-only publication transaction. Network operations bind to the
literal authority through an isolated Git configuration and private empty
template. The transaction derives signature scope only from the exact target-tip
object ID reported by a forced, pruned temporary fetch, traverses raw object links
with commit-graph and bitmap acceleration disabled and outside replacement,
graft, and shallow views, requires an exact old-tip lease, and requires an exact
signed tip plus final remote readback.
The transaction tracks the real-push/readback interval explicitly: an interrupt
inside it reports unverified state and only the supported transactional retry,
while an earlier interrupt does not claim possible remote mutation.

Publication and activation are separate actions. Activation remains consumer-owned
and must be explicitly authorized for the target host. Preserve the previous
generation and any host-specific rollback mechanism until runtime acceptance is
complete.

## State and verification boundaries

- Agent Deck and tmux use `/tmp` as the persistent fleet socket parent.
- Generated agent leaves use collision preflight before Home Manager linking.
- `AI_NIX_BYPASS_MANAGED_CONFIG=1` bypasses Codex managed-profile
  classification and injection; host-local state safeguards still run.
- When managed configuration is present, the wrapper refuses
  `codex exec --ignore-user-config`; use the explicit bypass above when an
  unmanaged launch is intentional.
- Evaluation proves configuration construction, not deployment or runtime health.
- Runtime acceptance must inspect the active generation and the actual client or
  service behavior.

Verification tiers are intentionally distinct:

| Tier | Purpose |
| --- | --- |
| Pre-commit | Formatting, lint, parsing, and bounded essential tests |
| Pre-push | Commit signatures |
| Work-unit closeout | Slow focused tests, consumer evaluation, and affected builds |
| Scheduled/expensive | Cross-system portable evaluation, native checks, and low-frequency evidence |
| Runtime | Native activation and service/client acceptance |

Names must represent real evidence. A coverage, soak, fuzz, or parity claim is valid
only when that behavior actually ran.

`test/check-manifest.nix` classifies every root and portable check on each
supported system. Closeout evaluates the gates classified as evaluation-only and
builds every behavioral check; `make test` selects its bounded subset from that
same manifest rather than maintaining another roster.

## Change rules

- Change one authority and derive every projection.
- Fix shared behavior once at its narrowest seam.
- Search maintained consumers before deleting compatibility.
- Keep generated shared-home leaves identical and mutable state host-local.
- Keep publication, activation, and destructive cleanup independently authorized.
- Keep current architecture here; Git preserves completed execution history.
