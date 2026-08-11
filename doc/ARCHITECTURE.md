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

## Host registry and shared-home policy

`config/hosts/registry.nix` is the data authority for host system, activation,
login, the lean-server role, shared-work membership and rollout targets, and
shell host/output routing. `config/host-options.nix` gives those tables a typed
module surface and derives the capability flags consumed by modules.

The four active shared-work machines use one generated Home Manager
configuration. Their Nix-owned leaves must therefore remain byte-identical.
Dormant `git-ai` is also a canonical member of that policy class, but membership
does not claim present availability and does not add it to the explicit active
rollout. The registry classifies the shared home; each owning module remains
responsible for separating any per-machine mutable state from shared generated
leaves.

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
| `config/hosts/registry.nix` | Host identity, capabilities, membership, rollout selection, and routing data | Module or shell implementation |
| `config/hosts/shell-routing.nix` | Build-time shell projection of registry routing data | Independent host identity policy or runtime Nix discovery |
| `config/ai/catalog.nix` | Profiles, selectors, resources, validation | Client serialization or package builds |
| `config/ai/renderers/*` | Generated documents for one client | Global resource selection |
| `config/ai.nix` | Home Manager composition and ownership guards | Package implementation |
| `flake/ai.nix` | Portable package, app, and check composition | Host activation or root lock policy |
| `packages/*` | Reusable package sets and multi-consumer build/runtime implementation | Host selection |
| `overlays/*` | Ordered exposure, compatibility fixes, and cohesive integration-owned package definitions | Hidden host selection or unrelated configuration channels |
| `test/*` | Interface and integration contracts | Duplicate production algorithms |
| `bin/*` | Operator transactions | Implicit cross-repository mutation |

## AI configuration

```text
llm-setup-models-list -> llama-swap configuration and GPTel
oMLX /v1/models -------\
                         -> Pi startup discovery
llama-swap /v1/models --/

Nix client-local transport/default/override policy
  -> renderer adapters
  -> collision-checked generated leaves
  -> Home Manager preflight and activation
```

Nix owns endpoint wiring and client-specific policy, not a cross-client model
inventory. Codex retains its native catalog, Pi discovers local models at startup,
Droid receives no Nix-generated local-model list, and Prime Agent reuses the safe
Pi-compatible model overrides plus the shared local-provider discovery packages.
The catalog declares local inference endpoints once per catalog host. Profiles only
opt into those routes; the composer resolves the home's record once and passes it
to the renderers and activation logic that consume it.
The initial Prime Agent profile is Hera-only. Its prompt commands and Agent Skills
are direct catalog projections; static specialist definitions become native RLM
prompt adapters; stdio MCP remains available through the shared `pi-mcp-adapter`
because Prime Agent's native MCP integration accepts HTTP transports only.

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

Pi's packaging substrate is pinned through a dedicated `pi-llm-agents` input at
the exact revision whose Pi packaging matches the reviewed source build in
`packages/pi-source-build.nix` (record `pi-coding-agent-source-build` in
`sources/ai.json`). The floating `llm-agents` feed packages the other agents
and advances past that revision; because `flake/ai.nix` asserts the packaged
Pi version agrees with the reviewed source build, packaging Pi from the
floating feed fails at evaluation once the feed ships a newer Pi. The pin
costs an independent nixpkgs closure in `config/ai/flake.lock`; the
`llm-agents-nixpkgs-independent` check verifies both feeds keep their own
nixpkgs rather than following the consumer channel. Exit condition: when the
reviewed Pi source advances to the version the floating feed packages, retire
the pin as one unit — drop the `pi` entry from `agentFeeds` and rewrite
`canonicalPiPackages` and `upstreamPiPackage` in `flake/ai.nix` to read
`llm-agents`, remove `pi-llm-agents` from the `llm-agents-nixpkgs-independent`
feed list, drop the `pinnedPiPackage` assertions in
`test/ai/compatibility-check.nix`, and delete the input from
`config/ai/flake.nix`.

Pi gallery normalization has one implementation:
`packages/pi-gallery/normalization-policy.json` defines the closed policy and
`packages/pi-gallery/normalize-manifest.jq` executes it for both builds and updates.

## Source and update authority

`sources/*.json` owns updateable source coordinates, versions, and dependent
hashes. Native Nix derivations retain fetcher and build logic and load records
through `packages/source-catalog.nix`. Generated npm, Cargo, and flake locks remain
updater-owned projections beside their consumers.

`bin/update` performs the isolated repository update transaction. `make update`
requests the complete pull, update, validation, signed commit, exact-candidate
build and activation, publication, and push sequence. Homebrew is outside the
repository transaction.

Routine validation should use scoped outputs. Broad root checks can force unrelated
host-only inputs; the portable subflake exists so remote-safe checks can evaluate
the portable closure without them.

## Publication and activation

The repository has two authoritative remotes. A publication is complete only when
both point at the intended signed revision. `bin/publish` owns the dual-remote,
fast-forward-only transaction and mirror-race handling.

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
