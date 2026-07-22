# John's Node-RED patterns — concrete examples

Read this before generating a new flow. Each section shows the actual wiring style used in `/var/lib/node-red/flows.json`.

## Tabs at a glance

| Tab | UUID | What's on it |
|---|---|---|
| Away | `ba13e5bae3dfce24` | "Lockdown" inject + Anyone-Home/Nasim-Leaves/Vacuuming triggers; HVAC-off, lock-doors, ADT-arm-away, vacuum; sunset/sunrise "Evening" chronos pair |
| Schedule | `9fc588ef6d4255d1` | Rain-tomorrow change + Trash Day/Ruhi Book 9 calendar; Google reauth filter; `~Golden Hour till ~11 PM` porch-light scheduler |
| Institute Night | `16b059848fa0366b` | Calendar-driven pre-cool of all HVAC zones via `Turn on all HVAC` subflow |
| Pool Time | `c24adcfdbba9413b` | OpenUV forecast → compute UV-3 crossing → wait → TTS "Pool time" |
| Office | `cc0a523a4e3698a9` | `mac inactive/active`, `out of office`, `office door` → join-wait `confirmed absent` → purifier / HVAC eco |
| TV Room | `a9b4a9eb7416400c` | `TV on 2min` / `TV off 15s` → vacuum pause/resume + tv_room heat |
| Bedroom | `2562805da7746546` | Morning/evening heat schedule with door+presence gates, "phone Charging" → vacuum dock |
| Debug | `b644f53c72721acd` | OpenAI "Chat about an image" experiments, debug nodes |
| Schedules | `7c26648afb6a077c` | B-Hyve Programs A/B/C zone walkers, Pool 09:00–17:00, Spa Waterfall 10:00–12:00 |

## Subflows defined

### `Turn on all HVAC` (`cbd67853cf196bfd`)
Env: `Temperature:num=70`, `HVAC Mode:str=cool`.
Chain: `Set HVAC Mode` → delay 5s → `Set HVAC Temp` → delay 5s → `Turn on HVAC`.
All three service calls target the five climates `climate.{guest_bedroom,home_office,living_room,tv_room,upstairs}`.
JSONata: `$env("HVAC Mode")`, `$env("Temperature")`. No status output.

### `Act until observed` (`862be551b633e122`)
Env: `Repeat:num=1`, `Wait:num=5`, `State:str=on`, `EntityID:str=switch.smart_outdoor_plug_switch_1`, `Action:str=switch.turn_on`.
Chain: in → `chronos-repeat` (interval `$number($env("Repeat")) * 1000` ms) → `Check State` (`api-current-state` with `halt_if=${State}`, 2 outputs) → output 0 loops back to repeat AND to `set status` (function); output 1 → `Perform Action` (`api-call-service` with `action=${Action}`, `entityId=[${EntityID}]`) → subflow out.
Has a status output wired from `set status` (the success-detection branch). Used twice: "Turn on Outdoor Lights" (defaults) and "Turn off Outdoor Lights" (overrides `State=off`, `Action=switch.turn_off`).

## Trigger idioms

### chronos-scheduler → halt-if gate
6 of 12 chronos schedulers feed directly into an `api-current-state` for gating (B-Hyve Programs A/B/C → `rain delay?`; Bedroom `20:30–23:30` → `nasim home?`).

```json
{
  "id": "<scheduler-id>",
  "type": "chronos-scheduler",
  "z": "<tab-id>",
  "name": "Program A 23:00",
  "config": "f1c80506d19d3de2",
  "schedule": [{
    "trigger": {"type": "crontab", "value": "0 0 23 * * 2,4,6"},
    "output":  {"type": "msg", "property": {"name": "payload", "type": "str", "value": "Sac County Odd Addr"}}
  }],
  "disabled": false, "multiPort": false, "outputs": 1,
  "wires": [["<gate-id>"]]
}
```

### Sun-relative trigger with random spread
```json
{
  "type": "chronos-scheduler",
  "name": "Evening",
  "config": "f1c80506d19d3de2",
  "schedule": [
    {"trigger": {"type": "sun", "value": "sunsetStart", "offset": 0, "random": 60},
     "output":  {"type": "msg", "property": {"name":"payload","type":"num","value":"1"}}},
    {"trigger": {"type": "sun", "value": "night", "offset": 120, "random": 120},
     "output":  {"type": "msg", "property": {"name":"payload","type":"num","value":"0"}}}
  ],
  "multiPort": true, "outputs": 2
}
```
Two triggers with different outputs → `multiPort: true`, one wire array per output index.

### server-state-changed with embedded duration in the name
```json
{
  "type": "server-state-changed",
  "name": "mac inactive 15min",
  "entityidfilter": "binary_sensor.johns_mac_studio_active",
  "entityidfiltertype": "exact",
  "ifState": "off",
  "for": 15, "forType": "num", "forUnits": "minutes",
  "wires": [["<next>"]]
}
```
John embeds the dwell time in the node name. Single output is normal. `for: N` is HA-side dwell — entity must STAY in matching state.

### join-wait for multi-input debounce (rare — only once)
```json
{
  "type": "join-wait",
  "name": "confirmed absent",
  "paths": "mac_inactive,out_of_office",
  "pathsToWait": "mac_inactive,out_of_office",
  "timeout": "3600", "timeoutUnits": "1000",
  "useRegex": false, "warnUnmatched": false
}
```
Inputs set `msg.path` upstream (or use multiple `server-state-changed` with different topics). Output fires only when all paths arrive inside the timeout window.

## Gate patterns (`api-current-state`)

### "Continue when state matches halt_if" (output 0 wired)
Example: `john home?` in Office tab.
```json
{
  "type": "api-current-state",
  "name": "john home?",
  "version": 3, "outputs": 2,
  "server": "86b277e82b069e9b",
  "entity_id": "person.john_wiegley",
  "halt_if": "home", "halt_if_type": "str", "halt_if_compare": "is",
  "state_type": "str",
  "wires": [["<next>"], []]
}
```
Wires: `[[next], []]` → continue when person.john_wiegley == "home"; drop otherwise.

### "Continue when state does NOT match halt_if" (output 1 wired)
Example: `Anyone Home?` in Away tab.
```json
{
  "type": "api-current-state",
  "name": "Anyone Home?",
  "halt_if": "home", "halt_if_compare": "is",
  "wires": [[], ["<next>"]]
}
```
Wires: `[[], [next]]` → drop when someone IS home; continue when no one is home.

### JSONata halt (numeric comparison)
Example: `Last vacuum >5 days?`
```json
{
  "type": "api-current-state",
  "name": "Last vacuum >5 days?",
  "halt_if": "3 * 24 * 60 * 60",
  "halt_if_type": "jsonata", "halt_if_compare": "gt",
  "state_type": "num"
}
```

**The same `halt_if` value is used both directions in different tabs.** Always look at which output is wired to determine intent.

## HA service-call style — universal in this codebase

- `entityId` is always the array field.
- `dataType` is always `"jsonata"`.
- `data` is `""` when there's no extra payload.

```json
{
  "type": "api-call-service",
  "name": "purifier on",
  "server": "86b277e82b069e9b", "version": 7,
  "domain": "switch", "service": "turn_on",
  "entityId": ["switch.smart_plug_air_purifier"],
  "data": "", "dataType": "jsonata"
}
```

```json
{
  "type": "api-call-service",
  "name": "upstairs heat_cool 78-82",
  "domain": "climate", "service": "set_temperature",
  "entityId": ["climate.upstairs"],
  "data": "{\"hvac_mode\": \"heat_cool\", \"target_temp_high\": 82, \"target_temp_low\": 78}",
  "dataType": "jsonata"
}
```

```json
{
  "type": "api-call-service",
  "name": "Pool time TTS",
  "domain": "tts", "service": "speak",
  "entityId": [],
  "data": "{\"cache\": true, \"media_player_entity_id\": \"media_player.vlc_telnet\", \"message\": 'Pool time. UV is near 3, water is ' & $string($round($number(payload.pool_temp))) & ' degrees.'}",
  "dataType": "jsonata"
}
```

Mixed single/double quotes in JSONata: outer JSON uses double-quoted keys, inner strings can be single-quoted for `&` concatenation readability. `$round`, `$number`, `$string` are typical.

## Function node conventions

Only 6 functions in the codebase. Two shapes:

### Short — early-return filter or status emitter (≤12 lines)
```js
// filter: Google reauth
if (!msg.payload) return null;
if (msg.payload.event !== "reauth") return null;
msg.topic = "Google needs re-auth";
msg.payload = msg.payload.description;
return msg;
```

### Long — state machine / computation (50–80 lines)
- Date math with `Date` and `context.get/set` for dedup
- Multi-branch `node.status({fill, shape, text})` for visibility
- `node.warn()` for missing-data paths
- `return null` to drop a message
- 4-space indent (long) vs 2-space (short)
- Templated strings via backticks for status text

See `Pool Time` tab's `compute window` and the three `walk zones (Program A/B/C)` for canonical long-function examples.

## Layout

- Vertical bands stacked top-to-bottom; ~100–220 px gap between bands.
- Each band starts with a `comment` header at `x ≈ 150–200`, `y` = first row.
- Flow runs left-to-right within a band; nodes spaced ~220 px apart horizontally.
- Typical y values for first three bands: 40 (or 60 for comment, 120 for nodes), 220–280, 400–480.
- The Debug tab uses a tighter grid (x=14, y=19) — looks hand-pasted.

## Config-node IDs to inherit

| Config | UUID | Notes |
|---|---|---|
| HA server | `86b277e82b069e9b` | name "Home Assistant" |
| chronos-config | `f1c80506d19d3de2` | name "3413 Sierra Oaks Drive" (lat/long + tz) |

## Common entity IDs

### Climate (Nest)
`climate.upstairs`, `climate.guest_bedroom`, `climate.home_office`, `climate.living_room`, `climate.tv_room`, `climate.master_bedroom`

### Pool / Spa (IntelliCenter)
- Circuits: `switch.pool`, `switch.spa_waterfall`, `switch.spa`, `switch.jets`
- Heaters: `water_heater.pool`, `water_heater.spa`
- Sensors: `sensor.water_sensor_1`, `sensor.solar_sensor_1`, `sensor.vsf_power`, `sensor.vsf_rpm`, `sensor.vsf_gpm`, `sensor.air_sensor`
- Schedule indicators: `binary_sensor.pool_schedule`, `binary_sensor.spa_waterfall_schedule`
- Lights: `light.pool_light`, `light.spa_light`

### Sprinklers (B-Hyve)
- Run a zone: call `bhyve.start_watering` with `entity_id: switch.sprinkler_control_<zone>_smart_watering` and `minutes: N`. The device's own timer closes the valve.
- Rain delay: `switch.sprinkler_control_rain_delay` (`on`/`off`). Service: `bhyve.enable_rain_delay` with `hours: N`.
- Zone names exist for: front_yard, side_yard_right, drip_front_right, back_wall, zone_5 (unscheduled), around_dining_set, drip_front_left, along_driveway, back_of_house_and_side_yard_left, planter_box
- Program switches (cloud schedules): `switch.sprinkler_control_{trees,planter_box,sac_county_odd_addr}_program`

### Presence / doors
- `person.john_wiegley` (`home` / `not_home`)
- `binary_sensor.office_door_sensor_p2_office_door` (Matter device class `door`: `on`=open, `off`=closed)
- `binary_sensor.john_wiegleys_iphone_focus` (often `unavailable` — handle defensively)

### Mac activity (be careful)
- `binary_sensor.johns_mac_studio_active` — **flips on/off intermittently overnight from system wake events**, not user activity. Do not use as a presence signal.
- `sensor.johns_mac_studio_active_camera`, `sensor.johns_mac_studio_active_audio_input`, `sensor.johns_mac_studio_active_audio_output` — reflect real usage; states are `Active`/`Inactive`. Use these instead.

## Final reminders

- Generate UUIDs with `secrets.token_hex(8)` (Python) or `scripts/generate_uuid.py`.
- Confirm the `tab_id` (`z` property) is set on every node belonging to a tab.
- For status indicators on subflows, wire the success branch through a `function` that sets `msg.payload = {fill, shape, text}` to the subflow's status port.
- For per-zone sequential delays (sprinkler-style), use a single `function` with `setTimeout` (one msg per zone, spaced by `(minutes*60 + buffer) * 1000` ms). Don't unfold into N HA-call nodes with N chronos-delays.
