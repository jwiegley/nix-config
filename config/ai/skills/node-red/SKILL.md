---
name: node-red
description: Build, edit, and debug Node-RED flows on John's NixOS host (vulcan).
  Tuned to his actual plugin set, wiring conventions, naming style, and to the nodered_events
  PostgreSQL log + Grafana dashboard for chain tracing. Use whenever the user mentions
  Node-RED, flows.json, a flow tab name (Office, Schedule, Schedules, Pool Time, Away,
  Bedroom, TV Room, Institute Night, Debug), a Node-RED plugin or node type (chronos,
  api-call-service, api-current-state, server-state-changed, join-wait, actionflows,
  etc.), the Node-RED Events Grafana dashboard, or asks why a flow fired or didn't
  fire.
---
# Node-RED on vulcan

## Where things live

| Thing | Path / value |
|---|---|
| Flows | `/var/lib/node-red/flows.json` (Read/Edit as root via `sudo`) |
| Credentials | `/var/lib/node-red/flows_cred.json` (encrypted; back up with flows) |
| Settings.js source | `/etc/nixos/config/node-red-settings.js` |
| Settings.js runtime | `/nix/store/.../node-red-settings.js` (read-only — never edit in store) |
| Plugins via npm | `/var/lib/node-red/node_modules/` (Palette manager) |
| Plugins via Nix | NixOS overlay (template: `modules/services/node-red-event-logger.nix`) |
| Backup module | `/etc/nixos/modules/services/node-red-backup.nix` (30-day retention) |
| Service | `node-red.service`, user `node-red`, port `1880` |
| Restart | `sudo systemctl restart node-red` |
| Editor | `https://node-red.vulcan.lan/` |
| Running version | 4.1.10 (overlay-pinned: `/etc/nixos/overlays/node-red.nix`) |
| Event-log DB | Postgres `nodered_events` (peer auth via unix socket) |
| Event-log Grafana | `https://grafana.vulcan.lan/d/node-red-events` |
| Config-node IDs | HA server `86b277e82b069e9b`; chronos-config `f1c80506d19d3de2` |
| Admin API token | `/run/secrets/node-red-admin-token` (mode 0400 johnw:users; declared in `modules/services/node-red.nix` as `sops.secrets."node-red-admin-token"`) |
| Context persistence | **Enabled by default** via `contextStorage.default = {module:"localfilesystem"}` in settings.js. All `flow.set/get`, `global.set/get`, `context.set/get` calls persist to `/var/lib/node-red/context/`. No `'file'` arg needed. Cache + 30s flush. |

## How to edit flows — Admin API first, always

**Preferred: Admin API (`PUT /flow/<tab-id>`).** Live reload, no restart, no editor disconnect, surgical (only the named tab changes). This is the default path for any edit John asks for.

```bash
# Always read the token via shell substitution; never echo it.
TOKEN=$(cat /run/secrets/node-red-admin-token)
NR=http://localhost:1880

# Read all flows (returns array of nodes including tab/subflow definitions)
curl -sS -H "Authorization: Bearer $TOKEN" $NR/flows

# Read one tab (returns {id, label, nodes:[...], configs:[...], info, env})
curl -sS -H "Authorization: Bearer $TOKEN" $NR/flow/<tab-id>

# Replace one tab — surgical, leaves all other tabs untouched
curl -sS -X PUT -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d @updated-tab.json $NR/flow/<tab-id>

# Create a new tab (returns the new id)
curl -sS -X POST -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d @new-tab.json $NR/flow

# Delete a tab
curl -sS -X DELETE -H "Authorization: Bearer $TOKEN" $NR/flow/<tab-id>

# Replace the entire flows array (DESTRUCTIVE — use only when unavoidable)
curl -sS -X POST -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -H "Node-RED-Deployment-Type: full" \
     -d @flows.json $NR/flows
```

**Layout-preserving edits:** `GET /flow/<id>` → modify only the field that's wrong on the specific node(s) by `id` → `PUT /flow/<id>` with the same node array. Node coordinates, wires, and IDs are preserved because you sent them back unchanged.

**Token rules:**
- Always read via `$(cat /run/secrets/node-red-admin-token)` or assign to a shell variable. **Never** echo, log, or pass the token to a tool that surfaces output in this conversation. If a curl command would dump headers, redirect them to a tempfile.
- The token is owned by `johnw:users` mode `0400` — no `sudo` needed.

**Fallback paths (in order, only when the API can't help):**

1. **Editor UI** — for one-off edits John wants to make himself, or when a generated flow benefits from human review before publish. Output the JSON to `~/*.json`, suggest **Menu → Import → Select a file → Deploy**.
2. **Direct `flows.json` edit + restart** — only if Node-RED is down or auth is broken. Procedure: backup → `sudo` read/edit → `validate_flow.py` → `sudo chown node-red:node-red` → `sudo systemctl restart node-red`. ~6 s editor disconnect.

Don't write to `/var/lib/node-red/flows.json` directly when the API is reachable. Don't ask the user to re-import a tab when a `PUT /flow/<id>` would do the same job without losing the layout.

## House style — match this

Read every "House style" point below before producing a flow. Most of John's prior corrections trace to one of these.

### Time triggers
- Use `chronos-scheduler` (not stock `inject` with cron).
- Crontab values are **6-field CronosJS**: `0 0 23 * * 2,4,6` = sec min hour dom mon dow. Day-of-week list goes in the last field.
- Sun-relative: `type:"sun"`, `value:"sunsetStart"|"goldenHour"|"night"|...`, plus a `random` offset (15–240 min) to spread fires.
- Configs share `f1c80506d19d3de2` (location node).

### HA service calls (`api-call-service`)
- `entityId` is ALWAYS the array field. Single: `["switch.x"]`. Multi: `["climate.a","climate.b"]`. Script/scene: `[]`.
- `dataType` is ALWAYS `"jsonata"`. Never `"json"`.
- `data` is either `""` (no extra payload) or compact JSONata: `{"preset_mode": "eco"}`, `{"temperature": $env("Temperature")}`, TTS like `{"cache": true, "media_player_entity_id": "media_player.vlc_telnet", "message": '...' & $string(...) & '...'}`.

### State gates (`api-current-state` with `halt_if`)
- Default has **2 outputs**. Output 0 fires when state **matches** `halt_if`; output 1 fires when it does **NOT** match.
- John writes gates as questions: `anyone home?`, `office door closed?`, `john home?`. The question's "yes" answer routes to output 0; "no" to output 1.
- Wire ONE output to the continuation; leave the other empty. Pick which output based on plain-English intent.
- For comparisons, JSONata halt is supported: `halt_if_type:"jsonata", halt_if:"3*24*60*60", halt_if_compare:"gt"`.
- **DO NOT GUESS the direction.** Always read the existing wires for context. The same `halt_if` string is used both ways in this codebase.

### Naming
- Triggers carry their `for:` duration in the name: `mac inactive 15min`, `TV on 2min`, `Nasim leaves 15min`, `out of office 15min`.
- Gates are lowercase questions ending in `?`: `anyone home?`, `office door closed?`, `rain delay?`, `vacuum cleaning?`.
- Actions are imperatives or device-verb-param: `Turn off HVAC`, `purifier on`, `upstairs heat_cool 78-82`, `bedroom heat off`, `tv_room set 78 heat`.
- Inject buttons: time-shaped (`06:00 daily`, `Shut-off 23:15`) or state-shaped (`Lockdown`, `Turn on`).
- Schedulers: descriptive — `12:00-15:00`, `~Golden Hour till ~11 PM`, `Program A 23:00`, `Pool ON 09:00`.

### Layout
- Vertical bands per logical section, stacked top-to-bottom with ~100–220 px gaps.
- Comment-as-header anchors each band at `x ≈ 150–200`, `y` = first row of the band.
- Flow goes left-to-right within each band; comment uses sentence-headline style with em-dashes/ellipses: `When I leave the computer…`, `Pre-cool upstairs for Institute Nights`, `B-Hyve Program A — Sac County Odd Addr (Tu/Th/Sa)`.

### Subflow status output
Wire your "success" branch through a small function that emits `msg.payload = {fill, shape, text}` to the subflow's status port:
```js
const stamp = new Date().toLocaleString('en-US', {
  month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true
});
msg.payload = { fill: 'green', shape: 'dot',
                text: `${env.get('Action')} called : ${stamp}` };
return msg;
```
The runtime `TZ` is local, so no offset to hardcode. Pattern in production: subflow `Act until observed`.

## Top pitfalls (each has bitten us)

1. **`api-current-state` output direction.** Output 0 = match, output 1 = no-match. Same `halt_if` is wired both ways in different parts of the codebase. **Always check existing wiring**, never assume from the name alone. (See Office HVAC misfire — `office door closed? halt_if="off"` wired to output 0 means "fire when door IS closed".)
2. **`chronos-repeat` JSONata = milliseconds**, not seconds. Returning `5` is 5 ms. Use `$number($env("Repeat")) * 1000` for seconds.
3. **`chronos-repeat` "env" type doesn't read subflow env vars.** In a subflow context, switch the interval type to `jsonata` and use `$env("VarName")`.
4. **`server-state-changed` `for: N`** is HA-side: entity must STAY in matching state. Flickery sensors reset the dwell timer continuously. `binary_sensor.johns_mac_studio_active` is unreliable for presence — use `sensor.johns_mac_studio_active_camera` or `_audio_output` ≠ `Inactive` instead.
5. **`join-wait` reset semantics.** `msg.reset = true` silently drains the queue; `msg.complete` drains to the **expired** output. Don't conflate.
6. **Manage Palette can delete Nix-overlay plugins** during a Node-RED package version bump. If `node-red-event-logger` disappears, `sudo systemctl restart node-red-event-logger-install` re-installs it.
7. **node-red postgres role is INSERT-only** on `msg_events`/`audit_events`. Reads require `sudo -u postgres psql -d nodered_events`. Grafana queries fine.
8. **`msg.payload` truncation in event log** — 4096 UTF-8 bytes max. Large payloads stored as `{"_truncated": true, "preview": "..."}` with `payload_size` recording the original byte count.
9. **CronosJS cron is 6-field, not 5-field.** First field is seconds. `0 0 23 * * 2,4,6` not `0 23 * * 2,4,6`.
10. **`server-state-changed` v6 uses `entities: {entity: [...], substring: [...], regex: [...]}`**, NOT the flat `entityId`/`entityIdType` from older versions. Wrong schema → `TypeError: Cannot read properties of undefined (reading 'entity')` on startup, six errors for six nodes, etc. Always use the nested form when emitting JSON for v6.
11. **`api-call-service` v7 needs `action: "<domain>.<service>"`** in addition to the legacy `domain`/`service` fields, plus `floorId: []`, `labelId: []`, and `blockInputOverrides`. Omitting any of these makes the editor flag the node as invalid (red triangle) even though the runtime might still execute it. Reference example: the user's working `09238a6ff00540ec` node.
12. **`api-current-state` `outputProperties` valueTypes** that are actually valid: `entityState`, `entityId`, `jsonata`, `str`, `num`, `bool`, `flow`, `global`, `msg`, `env`, `date`, `bin`, `eventData`. The string `entity` is NOT a valid valueType — use `jsonata` with `$entity().attributes.<key>` to get attributes. Also include `override_topic: false` (working nodes always have it).
13. **Never echo or log the Admin API token.** When using `/run/secrets/node-red-admin-token`, wrap it in `$(cat …)` or assign to a shell variable that's only consumed by curl. If you need to see whether the token works, check the curl HTTP code (`-w "%{http_code}"`) and response length — never the request headers.
14. **Palette/API installs need `bash` in the service PATH.** Many npm packages (e.g. `core-js`) have postinstall scripts that spawn `sh`. The default `node-red.service` PATH on this host (`nodejs, gcc-wrapper, coreutils, findutils, grep, sed, systemd`) has no shell — installs ENOENT with `npm error syscall spawn sh`. Fixed by `systemd.services.node-red.path = [ pkgs.bash ];` in `modules/services/node-red.nix`. Anytime an install fails with "spawn sh ENOENT", verify the service path still has bash.

## Debugging workflow

Event log captures `onSend` and `onComplete` for every node into Postgres. Primary UI: Grafana → `Node-RED Events` dashboard. SQL backup if Grafana is offline.

**"X didn't fire":**
```sql
SELECT ts, msgid, topic, payload FROM msg_events
WHERE node_id = '<trigger-uuid>' AND hook = 'onSend'
  AND ts > now() - INTERVAL '24 hours'
ORDER BY ts;
```
Zero rows → upstream issue. Rows present → drill in via msgid.

**"X fired when it shouldn't":**
1. Find the actuator's `onSend` in Grafana panel "All events" (filter `node_name`, hook=`onSend`).
2. Copy the msgid → dashboard variable `$msgid`.
3. Read the trace panel top-to-bottom — first row is the trigger, each subsequent `onSend` is a hop. Find where a predicate wrongly evaluated true and inspect `payload` at that hop.

Full schema, retention rules, and more queries: `references/event_logging.md`.

## Plugin field guide

20+ contrib plugins installed. Used heavily:
- `node-red-contrib-home-assistant-websocket` — main driver.
- `node-red-contrib-chronos` — every timer / sun trigger / "act until observed" loop.
- `node-red-contrib-join-wait` — multi-input debounce (canonical: Office `confirmed absent`).
- `node-red-contrib-postgresql` — used internally by the event logger.
- `node-red-contrib-actionflows` — only in the `Act until observed` subflow.
- `node-red-debugger` — plugin (sidebar), not nodes; off by default.

Lesser-used: collector, bool-gate, boolean-logic-ultimate, pid-controller-isa, prometheus-exporter, simple-gate, threshold-control, openai-api, email, ping, prowl, introspection.

Per-plugin pitfalls + idiomatic usage: `references/plugins.md`.

## Domain entities (HA)

Quick recall list — full catalog and tab UUIDs are in `references/patterns.md`.

- Climates (Nest): `climate.{upstairs,guest_bedroom,home_office,living_room,tv_room,master_bedroom}`
- Pool (IntelliCenter): `switch.{pool,spa_waterfall,spa,jets}`, `water_heater.{pool,spa}`, `sensor.{water_sensor_1,solar_sensor_1,vsf_rpm,vsf_gpm}`, `binary_sensor.{pool_schedule,spa_waterfall_schedule}`
- Sprinklers (B-Hyve): zones via `switch.sprinkler_control_<zone>_smart_watering` (call `bhyve.start_watering` with `minutes`), rain delay `switch.sprinkler_control_rain_delay`
- Presence: `person.john_wiegley` (`home`/`not_home`), `binary_sensor.office_door_sensor_p2_office_door` (Matter: `on`=open, `off`=closed)
- Mac activity: prefer `sensor.johns_mac_studio_active_camera`/`_audio_output` over `binary_sensor.johns_mac_studio_active`.

## When to load references

- Plugin gotcha or unsure of node config → `references/plugins.md`
- Event-log query or Grafana panel → `references/event_logging.md`
- Reproducing John's wiring style on a new tab → `references/patterns.md`
- Function node code patterns → `references/function_snippets.md`
- Admin API or generic node schema lookup → `references/api_reference.md`, `references/node_schemas.md`

## Available scripts

- `scripts/generate_uuid.py [count]` — Node-RED 16-char hex UUIDs
- `scripts/validate_flow.py <file>` — JSON + wire integrity
- `scripts/wire_nodes.py <file> <src> <tgt> [output]` — programmatic wiring
- `scripts/create_flow_template.py <type> [out]` — generic boilerplate (mqtt/http-api/data-pipeline/error-handler). **These are not in John's style** — use as scaffolding only.

## Things to avoid offering

- Don't use Manage Palette to install a new plugin permanently — Nix overlay is the right vehicle.
- Don't suggest `~/.node-red/` paths; those don't exist on this host.
- Don't write to `flows.json` directly when the API is reachable — use `PUT /flow/<id>` for surgical, layout-preserving updates.
- Don't ask the user to re-import a tab to apply a small fix — fetch with `GET /flow/<id>`, patch, `PUT /flow/<id>`. Same end state, no manual work.
- Don't propose mocking the event-logger DB in tests — use real Postgres (CLAUDE.md rule).
- Don't fabricate entity IDs — verify against `/var/lib/hass/.storage/core.entity_registry` (jq filtered by platform).
