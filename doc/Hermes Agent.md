# Hermes Agent on Hera

## Status and scope

This document defines the operating contract for a native Hermes Agent service
on Hera. Hermes runs directly in John's graphical login session, without a
container or command broker, and may use the host's filesystem, network,
development tools, signing agent, and explicitly granted root authority. The
configuration nevertheless keeps package, service, state, credential, and
remote-access ownership distinct, so that each boundary can be inspected and
rolled back independently.

This implementation session stops before activation. It does not install the
stable application, grant macOS privacy access, publish a Tailscale Serve route,
start Hermes, alter Qdrant, or establish runtime health. Evaluation and build
evidence remain distinct from those later operations (see
[`ARCHITECTURE.md`](ARCHITECTURE.md#state-and-verification-boundaries)).

The volatile upstream and host facts in this document were last checked on
2026-08-24. Reconfirm them when advancing Hermes, macOS, Home Manager, oMLX, or
Tailscale.

## Architecture and ownership

The design has one service owner and one configuration owner. The pinned Hermes
Home Manager module owns installation, managed-state initialization, the complete
configuration leaf, and the sole LaunchAgent; this repository supplies the
catalog selection, the concrete renderer, reusable integration packages, a
credential-injecting runtime wrapper, and Hera-specific host policy.

```text
Conduit on iPhone
  -> private Tailscale Serve HTTPS route (external mutable state; no Funnel)
  -> 127.0.0.1:8642 (Hermes OpenAI-compatible API)
  -> one upstream Home Manager LaunchAgent
  -> stable signed Hermes Agent Service.app supervisor
  -> Keychain-backed Hermes runtime package
       |-> 127.0.0.1:8000/v1       oMLX inference and embeddings
       |-> qdrant.vulcan.lan       assistant memory
       |-> vulcan.lan:5432         read-only org database
       |-> local stock-trader MCP  external market data and analysis
       `-> searxng.vulcan.lan      native web search
```

| Authority | Responsibility | Excluded responsibility |
| --- | --- | --- |
| `config/ai/catalog.nix` | The `hera-hermes` profile, model, endpoint, MCP, plugin, and tool selection | Hermes serialization, credentials, and host activation |
| `config/ai/renderers/hermes.nix` | Translation of the complete selected catalog into Hermes configuration | Global selection and mutable state |
| Hermes `services.hermes-agent` Home Manager module | Package installation, `$HERMES_HOME` managed marker, exact config replacement, plugin links, and the one user LaunchAgent | Root policy, TCC grants, and Tailscale Serve state |
| Runtime package wrapper | Required Keychain lookups and fixed nonsecret process environment | Credential values in Nix or a second service lifecycle |
| Stable signed app supervisor | A durable macOS service identity and transparent child supervision | Hermes configuration or a second LaunchAgent |
| `config/darwin.nix` | Hera-only sudo policy and host Nix settings | Hermes client serialization |
| Vulcan | Qdrant, PostgreSQL, SearXNG, their TLS endpoints, server credentials, and server monitoring | Hera's client configuration, local Stock Trader MCP process, and LaunchAgent |

The upstream module's launchd attribute is augmented at individual leaves; it is
not copied or replaced. There is exactly one Hermes job, under the upstream label
`org.nix-community.home.hermes-agent` (Hermes v0.20.5 Home Manager module).

## Versioned Hermes and model contract

Hermes is pinned to release 0.20.5, tag `v2026.8.19`, at the full revision
[`fcbd1076a93841fa88855acce810e342a5b78101`](https://github.com/NousResearch/hermes-agent/commit/fcbd1076a93841fa88855acce810e342a5b78101).
Upstream describes Nix support as Tier 2 and advises release-based pins rather
than `main` ([Hermes Nix documentation at the pinned release](https://github.com/NousResearch/hermes-agent/blob/v2026.8.19/website/docs/getting-started/nix-setup.md)).
The revision and the Nix lock content hash establish the selected source bytes;
the upstream tag and commit were not cryptographically signed when inspected.

| Property | Managed value |
| --- | --- |
| Driving model | `DeepSeek-V4-Flash-0731-oQ8e-mtp` |
| Inference API | `http://localhost:8000/v1` |
| Context window | 262144 tokens |
| Hermes API bind | `127.0.0.1:8642` |
| Advertised API model | `DeepSeek-V4-Flash-0731-oQ8e-mtp` |
| Auxiliary model work | The same local model and endpoint, or disabled |
| Cloud fallback | None |
| Hermes desktop/backend mode | `none`; the gateway carries the API |

The API adapter rejects a missing, weak, or placeholder bearer key, including
on loopback, and server-side requests may invoke Hermes terminal tools (Hermes
[API-server documentation](https://github.com/NousResearch/hermes-agent/blob/v2026.8.19/website/docs/user-guide/features/api-server.md)). Treat its bearer
credential as a remote-code-execution credential.

Hermes updates pass through the Nix input pin, package build, module-contract
tests, and system review. Managed mode disables Hermes's imperative setup,
configuration editing, gateway installation, and self-update commands; the Nix
revision remains the software authority (Hermes v0.20.5 Nix documentation).

## Configuration, migration, and mutable state

The service uses `HERMES_HOME=/Users/johnw/.hermes`. Nix owns only the leaves
that must remain reproducible; it does not own the directory as a whole.

| Nix-managed leaf | Contract |
| --- | --- |
| `~/.hermes/config.yaml` | Complete nonsecret configuration, serialized as JSON-valid YAML and replaced authoritatively through upstream `configFile` |
| `~/.hermes/.env` | Complete nonsecret API baseline, rewritten so that stale secret assignments cannot override Keychain injection |
| `~/.hermes/.managed` | Upstream Home Manager ownership marker |
| `~/.hermes/plugins/nix-managed-*` | Authoritative links for the selected Qdrant-memory and local-extraction plugins |
| Hermes LaunchAgent and stable app template | Service lifecycle and reproducible app contents |

The renderer supplies `terminal.cwd=/Users/johnw` explicitly and leaves
upstream `settings` and `mcpServers` empty. At Hermes 0.20.5 the `settings` path
recursively preserves old on-disk keys that disappear from Nix; `configFile`
instead replaces the complete leaf and therefore gives removal an exact meaning
(Hermes v0.20.5 `moduleCommon.nix` and `configMergeScript.nix`).

Sessions, auth state, file memories, cron state, logs, caches, and other runtime
records beneath `~/.hermes` remain mutable. Nix activation neither deletes nor
recreates them. Qdrant points in the remote `assistant` collection are likewise
external mutable state.

Before the first activation, record the owner and permissions of the existing
`~/.hermes`, and make a recoverable backup without printing its contents. The
first managed activation deliberately replaces `config.yaml` and the nonsecret
`.env` baseline; retain the backup until the new service has passed runtime
acceptance. Do not run `hermes setup` or `hermes config edit` against the managed
home.

## Credentials and the login session

Nix records only environment names and Keychain service/account metadata. The
runtime wrapper retrieves every required value from John's unlocked login
Keychain and fails before starting Hermes when a value is absent or inaccessible.

| Environment name | Keychain service | Account | Purpose |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | `nix-config.omlx-hera-client` | `johnw` | Local oMLX authentication |
| `API_SERVER_KEY` | `nix-config.hermes.api-server-key` | `johnw` | Conduit/Hermes API bearer authentication |
| `QDRANT_API_KEY` | `nix-config.hermes.qdrant-api-key` | `johnw` | Vulcan Qdrant authentication |
| `PGPASSWORD` | `nix-config.hermes.org-db-password` | `johnw` | Read-only org PostgreSQL role |

Provision the items through the approved Keychain procedure, with no value in a
shell argument, Nix expression, generated file, plist, process argument, test
fixture, or log. Authorize only the reviewed login-session lookup path for
noninteractive access. The private key for app signing remains a separate
Keychain object.

The per-user LaunchAgent depends on John's graphical login session and unlocked
login Keychain. It does not run before login and stops at logout. A pre-login
daemon would require a separate system-Keychain and LaunchDaemon design; it is
outside this contract.

## Native macOS service identity

The upstream Home Manager job remains the sole LaunchAgent. Its service package
passes execution through a fixed, signed supervisor at:

```text
/Users/johnw/Applications/Hermes Agent Service.app
```

The application uses bundle identifier `com.newartisans.hermes-agent`, declares
`LSBackgroundOnly`, and carries a Local Network usage description. The
LaunchAgent retains the upstream label, working directory, restart policy, and
log paths; adds the same bundle identifier through
`AssociatedBundleIdentifiers`; and uses launchd `ProcessType=Standard` so that
Hermes is not assigned the background process class. The supervisor preserves
the child's arguments, environment, current directory, standard descriptors,
exit status, and forwarded termination signals.

Activation builds a sibling app, signs it with the persistent public identity
`Apple Development: jwiegley@gmail.com (Y546N259NB)`, verifies the designated
requirement, and atomically replaces the fixed app only after verification. The
identity string is public metadata; no signing key enters Nix. An absent,
ambiguous, expired, or mismatched identity aborts activation before Home Manager
sets up the LaunchAgent.

Nix and `tccutil` cannot grant macOS privacy access. After the first authorized
activation installs the fixed app, grant that exact app Full Disk Access and
Local Network access in System Settings. Do not grant Accessibility,
Automation, Screen Recording, camera, or microphone access until requested work
requires the particular class. Passwordless sudo does not replace TCC consent.

## Native integrations

### Qdrant memory

Hermes uses the vendored Qdrant memory plugin at revision
`c350be1e843de820966f5a1db52b29b22b7775b9`. It connects to
`https://qdrant.vulcan.lan`, selects collection `assistant`, and fails closed if
`QDRANT_API_KEY` is unavailable. Dense embeddings come from Hera's
`bge-m3-mlx-fp16` oMLX model with dimension 1024; local BM25 arithmetic supplies
the sparse vector; and retrieval uses Qdrant's IDF and reciprocal-rank fusion.
The deployed configuration records raw user/assistant turn pairs through
`sync_turn` and mirrors explicit Hermes memory writes. Session switches update
the active scope only. Automatic fact extraction at pre-compression and session
end remains disabled by the vendored default unless it is deliberately enabled
in a later reviewed configuration (vendored plugin source and Vulcan service
configuration, inspected 2026-08-24). If extraction is enabled later, extracted
facts deliberately carry no turn provenance: raw Hermes transcript indexes
cannot be correlated truthfully with completed `sync_turn` pairs without a
stable upstream correlation key.

The collection name is a namespace only. Vulcan currently uses one global
Qdrant API key and does not issue a principal restricted to `assistant`; the
same credential can address other collections. Issue `nix-uasn` records the
separate JWT-RBAC work required for an authorization boundary.

`qdrant_forget` deletes one exact in-scope memory ID immediately. It does not
add a second approval token or confirmation service: this follows the accepted
full-autonomy policy. Preview remains available for ambiguous requests, but the
request and exact-ID scope check are the operating controls.

No declared Qdrant snapshot/export job or restore test presently protects
`assistant`, and `/var/lib/qdrant` resides on Vulcan's ext4 root rather than a
covered ZFS dataset. Issue `nix-7v7o` records the required native snapshot,
retention, alerting, and restoration proof. Until that issue is complete, memory
recovery is not established.

### org-db

The local stdio MCP exposes exactly two tools: `org_sql` and `org_search`.
`org_sql` accepts one `SELECT` or `WITH ... SELECT`, rejects statement smuggling,
mutation terms, timeout changes, backend signaling, advisory locks, notification,
and sequence mutation, constrains the outer result to 1–1000 rows, and executes
in a read-only PostgreSQL transaction. A 5-second connection timeout precedes a
15-second statement and whole-cursor wall-clock limit plus a 5-second lock
timeout; each row and the aggregate tool output are capped at 1 MB. Parser checks
are not a hostile-SQL sandbox: Vulcan's dedicated `openclaw` role has CONNECT,
schema USAGE, and SELECT on current and future tables, while its server-side
EXECUTE grants remain the authority for extension and user-defined functions
(Vulcan database and extracted MCP source, inspected 2026-08-24).

The nonsecret client settings are:

```text
PGHOST=vulcan.lan
PGPORT=5432
PGDATABASE=org
PGUSER=openclaw
PGSSLMODE=verify-full
PGSSLROOTCERT=<Nix-managed combined CA bundle>
ORG_CONFIG=/Users/johnw/.config/org/config.yaml
ORG_DB_BASE_URL=http://127.0.0.1:8000
ORG_DB_MODEL=bge-m3-mlx-fp16
```

`ORG_DB_BASE_URL` omits `/v1` because `org-jw` appends
`/v1/embeddings`. If its CLI requires `--api-key`, the wrapper supplies the
nonsecret sentinel `unused`; no credential is placed in process arguments.

### Stock Trader

Hermes reuses the repository's existing `stock-trader-mcp` package and applies
an exact include-list. The available surface contains these 18 read and
analysis operations:

1. `get_quote`
2. `get_price_history`
3. `get_technical_analysis`
4. `get_news_sentiment`
5. `check_data_source_status`
6. `scan_market`
7. `analyze_options`
8. `assess_trade_risk`
9. `get_av_news_sentiment`
10. `get_forex_rate`
11. `get_crypto_quote`
12. `get_commodity`
13. `get_insider_transactions`
14. `get_etf_profile`
15. `get_earnings_calendar`
16. `get_ipo_calendar`
17. `get_listing_status`
18. `get_historical_options`

There is no account, portfolio, order, buy, sell, cancel, or trade-execution
tool in this projection. `analyze_options` and `assess_trade_risk` use HTTP POST
for computation but do not place a trade (pinned Stock Trader MCP source,
inspected 2026-08-24). The exact include-list prevents a later upstream tool
from becoming available merely because the server adds it.

### Web search and extraction

Search uses Hermes's native SearXNG backend at
`https://searxng.vulcan.lan`; it is not represented as an MCP server. Content
extraction uses the local plugin and its isolated `trafilatura` worker. Keyless
web fallbacks and rescue providers are disabled.

The extractor accepts at most ten HTTP(S) URLs per call, rejects every
non-global destination, pins each connection to the public address that was
validated, and revalidates every redirect before following it. Curl transfers
and redirects share a 20-second budget per URL; synchronous DNS is not
interruptible at that inner deadline, so a 230-second subprocess timeout is the
hard outer bound on the entire batch. The worker caps HTML at 20 MB and
extracted text at 200,000 characters, bypasses ambient proxy configuration,
strips ambient secret variables, and removes URLs from diagnostics. The pinned
Hermes dispatcher is patched at the portable package seam so that its own
INFO/debug records also contain only result indices, counts, and sizes. No
intermediary extraction service receives a URL or page content, although the
requested origin necessarily receives the normal HTTP request (vendored and
pinned sources inspected 2026-08-24). These bounds limit one tool invocation;
they do not sandbox Hermes itself.

## Autonomy and resource policy

Hermes has no command allow-list, approval broker, or container boundary. Its
terminal approvals are disabled, and it may sign commits, push revisions, run
builds, and activate systems when the request calls for those actions. The
request supplied to Hermes is therefore the principal operating control.

Hera grants `johnw` the equivalent of:

```text
johnw ALL=(ALL:ALL) NOPASSWD: ALL
```

The rule is Hera-only and is absent on Clio and Linux projections. It grants
root-equivalent authority to every process running as `johnw`, not solely to
Hermes. It does not bypass the login Keychain or all macOS privacy decisions.

Hermes uses the existing login GnuPG and SSH agent, `GNUPGHOME`, Git signing
configuration, and signing key `ed25519/12D70076AB504679`; it does not create a
private agent or smart-card dependency. `GPG_TTY` is absent from the LaunchAgent
environment. The login Keychain and GnuPG authorization still require a
post-reboot acceptance test.

The Hermes process constrains only Nix scheduling:

```text
max-jobs = 1
cores = 8
```

Those are the complete Hermes-specific Nix resource controls. There is no
CPU-affinity policy, CPU set, `taskpolicy`, or processor-number selection.

## Conduit and private remote access

Hermes's OpenAI-compatible API listens only on `127.0.0.1:8642`; it never binds
to a LAN or wildcard address. Conduit uses the resulting private tailnet HTTPS
origin and the independent `API_SERVER_KEY`. The local `/health` route supplies
unauthenticated liveness, while detailed health, model enumeration, and chat
require bearer authentication (Hermes v0.20.5 API-server contract).

Tailscale Serve is external mutable state. Ordinary Nix or Home Manager
activation does not create, replace, or remove its route. After local Hermes
acceptance:

1. Run `hermes-agent-ops serve-status` and retain the redacted structural result.
2. Stop if an unrelated or unexpected Serve configuration is present.
3. Run `hermes-agent-ops serve-apply`. It applies a mapping to
   `http://127.0.0.1:8642` only when the current Serve state is empty, accepts
   the exact existing private mapping idempotently, and refuses Funnel or any
   unrelated nonempty state.
4. Re-run the status check; prove the expected private mapping and the absence
   of Funnel before configuring Conduit.
5. Enter the resulting tailnet URL and bearer credential in Conduit without
   recording either credential value in this repository.

Do not guess or silently reconcile an existing Serve configuration. Route
application and removal are separately authorized network mutations
([Tailscale Serve documentation](https://tailscale.com/kb/1242/tailscale-serve)).

## Monitoring and evidence

Monitoring separates process, component, and end-to-end evidence. Passive
health is useful, but it does not show that the selected model answered a
request.

| Check | Evidence | Limit |
| --- | --- | --- |
| `launchctl print gui/$(id -u)/org.nix-community.home.hermes-agent` | One loaded user job, restart state, and exit status | Does not prove API or model health |
| `hermes-agent-ops health` | Loopback API liveness | Public and component-only |
| `hermes-agent-ops health --detailed` and `/v1/models` through a redacted check | Required credentials load and the advertised model is exact | Does not prove a generated answer |
| oMLX readiness and exact model inventory | Local inference dependency is present | Does not prove Hermes routing |
| MCP initialization and tool enumeration | `org-db` and the exact Stock Trader surface are registered | Does not prove a successful query |
| Local-extraction empty-list probe | Plugin discovery and worker execution | Does not fetch external content |
| `hermes-agent-ops serve-status` and a Conduit request | Private route and client reachability | External mutable state; not activation evidence |

Logs remain beneath John's private `~/.hermes/logs` state with restrictive
permissions. Never log a resolved environment, bearer header, database
password, memory payload, prompt, or Conduit request body.

A deliberate, bounded model-answer probe belongs to first activation and
periodic acceptance, not a frequent passive monitor. Mark or exclude its session
from memory collection so that monitoring cannot populate `assistant`. Qdrant
server, snapshot, and restore-age monitoring remain Vulcan's responsibility.

## Review and first activation

### Non-activation gates

The review candidate is complete only after the exact uncommitted diff has
passed repository parsing, focused Hermes contracts, the ordinary test surface,
portable evaluation, and a full Hera build. The standard non-activation commands
are:

```sh
make verify-inputs
test/bin/unittest-strict.py test/bin/update-overlay-slow-test.py
nix flake check ./config/ai --all-systems --no-build
make test
./build system
```

Inspect the rendered config, final LaunchAgent, stable-app requirement, host
scoping, credential metadata, exact MCP tool lists, and absence of secret values.
Do not call evaluation or build success an activation or runtime result. This
implementation session does not run `make switch`.

### First authorized activation

When review and activation are separately approved:

1. Preserve the current Darwin generation, the valid stable app if one exists,
   and the recoverable `~/.hermes` backup.
2. Provision the four generic-password items, app-signing identity access, and
   required Keychain ACLs before starting the service.
3. Run `make verify-inputs` and `make build` from Hera's authoritative
   `~/src/nix` checkout.
4. Run `make switch`. The activation signs and installs the stable app before
   Home Manager sets up the LaunchAgent.
5. Grant the stable app Full Disk Access and Local Network access in System
   Settings.
6. Complete the local acceptance checklist below before publishing a Tailscale
   Serve route.
7. Apply and verify the separately authorized private Serve transaction, then
   test Conduit from the tailnet.

### Runtime acceptance

Acceptance requires all of the following evidence on the active generation:

- the fixed app passes `codesign` verification and its designated requirement
  names the expected signer and bundle identifier;
- one healthy LaunchAgent has the upstream label and the stable app remains the
  responsible supervisor parent;
- all required Keychain lookups succeed from the LaunchAgent without UI and
  without value disclosure;
- port 8642 listens only on loopback; unauthenticated protected routes fail;
  authenticated health, exact model enumeration, and a bounded answer succeed;
- oMLX serves `DeepSeek-V4-Flash-0731-oQ8e-mtp`; no cloud fallback is selected;
- Qdrant operations address `assistant`, and no Hera request addresses
  `memories`;
- `org_sql` remains transactionally read-only, `org_search` uses local
  embeddings, and Stock Trader advertises exactly the listed 18 tools;
- SearXNG search and bounded local extraction work without secret or URL
  disclosure in logs;
- a temporary repository creates and verifies a noninteractive commit signed by
  `12D70076AB504679`; SSH and harmless `sudo -n` probes succeed;
- the private Tailscale Serve route reaches the loopback API from Conduit, while
  Funnel and LAN listeners remain absent; and
- restart, login-session, and, when acceptable, cold-reboot checks repeat the
  credential, signing, and service evidence.

Cold-reboot autonomy remains unproved until the final check has actually run.

## Rollback

Rollback removes executable authority before touching data. If remote exposure
is material to the failure, remove the Tailscale Serve route through the
separately reviewed network transaction first; activation does not own that
state. Reactivate the retained previous nix-darwin generation through Hera's
authoritative checkout and native generation procedure, then repeat the process,
listener, and service checks.

Do not delete `~/.hermes`, the Qdrant `assistant` collection, Keychain items, or
the prior signed app as part of generation rollback. They are external or
mutable state and may be required for recovery. Restore the pre-activation
Hermes backup only after identifying a state-compatibility failure and approving
that separate data operation. A rollback is complete only when the previous
generation is active, the unexpected service/network authority is absent, and
the retained state remains readable.

## Known limitations

- `assistant` is not collection-isolated under the present global Qdrant key
  (`nix-uasn`).
- Qdrant memory has no established backup and restoration path (`nix-7v7o`).
- Full sudo autonomy makes every process under `johnw` root-equivalent; prompt
  care, API-key custody, and tailnet membership are the operative controls.
- The OpenAI-compatible API can invoke host tools. A leaked API bearer therefore
  crosses the complete Hermes trust boundary.
- TCC, Keychain ACLs, login state, Tailscale login, and Serve publication remain
  manual operating state.
- A per-user LaunchAgent cannot supply pre-login or logged-out availability.

These limitations are accepted for the initial native deployment. They are not
evidence that the corresponding risk has been removed.
