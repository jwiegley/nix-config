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

### External consumers

The supported shape is a paired root source and `dir=config/ai` input at one
revision.

External Home Manager and NixOS checkouts own their locks and activation. This
repository exports implementation and modules; it does not overwrite another
consumer's checkout or deployment state.

#### Vulcan consumer policy

Vulcan's `/etc/nixos/build` refreshes `nix-config`, `nix-config-ai`, and its
top-level Pi source while holding the consumer build lock, before ordinary
`nixos-rebuild` evaluation. The driver records the resolved revisions. Its NixOS
module graph remains on `nixos-25.11`; its Home Manager and standalone packages
use a separate `nixpkgs-user` input following the portable AI nixpkgs line.

VPS remains a supported external consumer but is parked outside the default
cross-consumer evaluation and active rollout sets. Its explicit consumer
evaluation and consumer-owned build driver remain available for deliberate
future updates.

## Host registry and shared-home policy

`config/hosts.nix` is the data authority for host system, activation,
login, declared home directories, DNS names and domains, NixOS host IDs, named
IPv4 addresses, host roles, shared-work membership, rollout targets, daemon and local-build capacity,
distributed-builder identity and client pools, and shell host/output routing.
Its shared `inferenceServices` ports drive the Nix-managed inference launchers
and catalog endpoints. Named resolver addresses reside in `networkPeers`, and
`probeHostGroups` supplies the configured blackbox monitoring groups.
Configured primary login IDs and home paths are projected from host rows, while
`userAccounts` records the additional NixOS accounts. `networkRanges` supplies the
LAN and Podman CIDRs used by the return-routing configuration.
For example, `hosts.clio.ipv4.wireguard1` supplies Clio's WG1 address to the gateway
policy without repeating the address. `config/host-options.nix` gives the host
tables a typed module surface
and derives the capability flags consumed by modules. Darwin projects each
builder's named SSH identity to its host-local key path and writes the resulting
ordered pool to `/etc/nix/machines`; the registry does not own private key
material.

The Vulcan and VPS flakes select their registry rows before choosing the package
system and pass those rows to their modules as `hostPolicy`. The owning networking
modules consume the declared hostname, with Vulcan also consuming its domain and
host ID. The `vulcan` and `ovh-vps` flake output names remain stable references.
Both flakes pass the complete host data as `hostRegistry` for cross-host
references and additional accounts. Generated hardware declarations retain
their existing ownership.

The `andoria` row supplies shared-work account, home, system, and activation
defaults. Each canonical shared-work member has a separate host row that inherits
those defaults and records its declared connection name. These records do not
infer system hostnames from connection names. The dormant `git-ai` row retains its
distinct SSH login without changing the owner of the shared Home Manager policy.
The Andoria consumer reads the shared defaults for its system, home settings,
terminal log path, local cache path, and local-account guard. Its `andoria-08`
evaluation identity and `jwiegley` flake output name remain stable references
rather than separate definitions of the account or system.

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
| `config/hosts.nix` | Host identity, capabilities, membership, rollout selection, daemon, local-build, and distributed-builder capacity, builder pools, and routing data | Module or shell implementation, private SSH key material, or activation |
| `config/hosts/shell-routing.nix` | Build-time shell projection of registry routing data | Independent host identity policy or runtime Nix discovery |
| `config/nix-trust.nix` | Shared binary-cache and client-signing trust data | Root-file installation or host activation |
| `config/ai/models.nix` | Managed model roles, provider overrides, context limits, provider availability, and retired model migration data | Runtime model inventory or endpoint discovery |
| `config/ai/catalog.nix` | Profiles, selectors, resources, validation, and composition of model roles | Client serialization or package builds |
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

`config/ai/models.nix` declares managed model roles, provider overrides, context
limits, provider availability, and retired names used by mutable-settings migration.
`codex.name` selects the default, while `codex.modelOverrides` holds independent
overrides for each model ID. Pi and Prime render the complete map. Codex projects
context-window overrides into its native catalog without changing membership or
order. Other metadata remains unchanged apart from the native serializer's rendered
instruction template. `codex.autoCompactPercent` determines the current default's
compaction threshold from its effective context window.
Nix owns those selections plus endpoint wiring and client-specific policy, not a
cross-client runtime inventory. Managed PAL obtains provider values from the user-owned
`$XDG_CONFIG_HOME/pal-mcp/config` file through a strict non-shell parser; Nix owns
only executable selection, typed environment names, and the generated MCP transport.
Managed Factory requests reuse the mutable Droid login and suppress explicit Factory
keys at the SDK boundary. The PAL resource is selected for Darwin, shared-work,
and Vulcan profiles and excluded from the VPS profile.
Pi renders its cached model snapshot
immediately, gives `/model` refreshes the upstream 15-second selector deadline,
and discovers local models at startup and through its native provider-refresh contract.
Droid receives no Nix-generated local-model list, and Prime Agent reuses the safe
Pi-compatible model overrides plus the shared local-provider discovery packages.
The catalog declares host-local inference endpoints once per catalog host for
fixed routes and non-Pi consumers. Darwin Pi receives a separate bilateral
discovery map: local llama-swap plus the stable `omlx-clio` and `omlx-hera`
providers. Both Pi homes therefore render the same provider identities while
retaining their host-specific fixed-route policy.

`recordings.llm` selects the cleanup model and provider for both the launchd command
and the generated transcription route. `recordings.asr` supplies the speech model
and language. The `pi-gpt-fast-mode` extension consumes the settings in `pi.fastMode`.
The `nixos` view preserves the runtime `/etc/models.json` schema and the
service-specific retry and context budgets. NixOS modules import that view from
the paired shared source input.

The generated `ai/model-policy.json` leaf under `XDG_CONFIG_HOME` exposes the
non-secret policy to Emacs. Its `emacs` view owns configured model families and
instances, GPTel models, preset parent assignments, inference overrides, and
llama-swap resident/preload selections. `llm-setup` materializes these definitions
as its existing model structs instead of maintaining a second literal list.
Runtime discovery remains read-only for Nix-managed definitions. Reloading the
library and preset definitions refreshes the registered
settings after activation without rewriting active request state. The companion
`ai/host-policy.json` leaf projects host details from `hosts.nix`, including the
current home class and model-tool endpoints. Both JSON files are generated
views, not editable authorities.

The `scripts` view supplies launch defaults, conversion models, inference token
budgets, and MLX benchmark cases. The scripts repository consumes the generated
JSON through `model_policy.py`, without runtime Nix evaluation. Explicit
per-invocation model choices retain their existing precedence.

The `agentCat` view defines the existing routing selectors, personas, and ordered
fallback chains. The `agent-cat-routing` host role selects the generated
`agent-cat/routing.yaml` leaf, currently on Hera only. Its renderer emits version
2 without secret declarations. Stable profile names are references and do not
select models by their spelling. The Emacs persona does not redirect GPTel calls.

The managed-file preflight refuses to replace an existing regular routing file.
Initial adoption preserves that file before linking the generated leaf, without
claiming the containing directory or mutable runtime state. Offline inspection
validates the routing document but leaves exact model selectors static-unverified.

The `advisors` view selects PAL partners, validation models, and Forge model
aliases. Shared Markdown renderers expand the named `NIX_MODEL` template fields.
Model-dependent skills are materialized by `agent-resources` before deployment.
Their source templates do not define a second editable model roster.

Packaged upstream model catalogs remain inventories rather than policy. The Pi
source-build catalog addition supplies missing upstream model metadata without
selecting that model for a client.

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
artifacts with the maintained `github:jwiegley/pi` source through the `flake =
false` `pi` input owned by the portable subflake. Root consumes that input
transitively; root and portable locks plus the catalog projection must resolve
the same immutable fork commit. The `pi-coding-agent-source-build` catalog
record carries the matching version, NAR projection, npm dependency hash, and
packaged provider-data artifact. `packages/pi-source-build.nix` fails evaluation
unless those projections match the locked input, and `flake/ai.nix` separately
requires the feed package and source build to have the same version. The wrapper
requires `dist/bundle/cli.js` at build time and publishes `bundledCliAbi = 1`, so
an accidental modular-entrypoint fallback fails the package and gallery gates.
The `llm-agents-nixpkgs-independent` check keeps the feed's nixpkgs input
independent from the consumer channel.

The portable pin is deliberately immutable for shared fleet reproducibility. Vulcan
is the documented consumer-level exception: its external flake supplies a
top-level unrevisioned `github:jwiegley/pi` input and makes `nix-config-ai/pi`
follow it; its locked resolution is refreshed by the consumer build driver above.
That exception does not broaden or mutate the shared portable input.
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
distinct authorities.

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
| Pre-commit | Formatting, lint, and parsing |
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
