# Plugin field guide

One-screen reference per installed Node-RED contrib. Focus on pitfalls and idiomatic usage. Versions from the lockfile at `/var/lib/node-red/package-lock.json`.

## node-red-contrib-home-assistant-websocket (v0.80.3)

The Home Assistant bridge. Connects to HA websocket, subscribes to state changes/events, calls services, exposes Node-RED-defined entities back to HA.

**Most-used nodes:**
- **`api-call-service`** — invoke any HA service. Template rendering in target/data, queue-on-disconnect, optional Mustache. Data merge order: editor → message → flow.
- **`api-current-state`** — synchronous entity read. **2 outputs by default**: output 0 fires when `halt_if` matches, output 1 fires when it doesn't. Adds `timeSinceChangedMs`. `for:` requires entity to remain in matching state ≥ N units.
- **`server-state-changed`** — listener for state changes on selected entities. `If state` filter routes to output 2. `For` timer is HA-side semantics: cancels if entity leaves matching state. `event.old_state`/`event.new_state` plus `timeSinceChangedMs` in msg.
- **`server-events`** — raw HA event bus. Useful for non-state events (`call_service`, `automation_triggered`). Easily floods debug — never subscribe to "all".
- **`entity`** — declares a Node-RED-defined entity in HA. Entity ID derived from node name; renaming orphans the old entity.
- **`trigger-state`** — declarative entity triggers with multi-condition logic, separate outputs for matches/mismatches/conditions. Persists `is_enabled` across restarts.

**Pitfalls:**
- Numeric comparisons require `state_type: "num"`. Default is `str` so `"23.5" > 20` is string compare.
- HA long-lived token is in `flows_cred.json` — back up with flows.
- `for:` is HA-side, NOT a simple delay.

## node-red-contrib-chronos (v1.30.0)

Time scheduling, repeating, queueing, routing, filtering with SunCalc.

**Nodes:** `chronos-config`, `chronos-scheduler`, `chronos-state`, `chronos-repeat`, `chronos-delay`, `chronos-switch`, `chronos-filter`, `chronos-change`.

**Pitfalls:**
- **`chronos-repeat` JSONata mode returns MILLISECONDS.** If you return `5`, that's 5 ms — and below 86,400,000 (24h) it's treated as ms since midnight local time. Returning `5` ≠ 5s. For "5 seconds" use `5 * 1000`.
- **`chronos-repeat` `env` interval type does NOT resolve subflow env vars.** In a subflow, switch interval type to `jsonata` and use `$env("VarName")`.
- `chronos-config` location is shared; wrong coords break every sun computation silently.
- Cron is **CronosJS 6-field** (seconds first), not standard 5-field. `0 0 23 * * 2,4,6` is sec-min-hour-dom-mon-dow.
- Schedules reset on Node-RED restart unless context is persisted; rolling deploys can re-roll `random` offsets.

**Example schedule entry:**
```json
{"trigger": {"type": "sun", "value": "sunsetStart", "offset": 0, "random": 60},
 "output":  {"type": "msg", "property": {"name":"payload","type":"num","value":"1"}}}
```

## node-red-contrib-join-wait (v0.6.3)

Joins related messages across multiple paths within a time window. Exact-order, regex, correlation grouping, reset, queue persistence.

**Pitfalls:**
- Not a replacement for stock `join` — for `msg.parts`/split flows, use stock.
- Any-order regex: paths counted greedily left-to-right. `["path_[12]", "path_2"]` never completes because `path_2` matches the first regex first.
- `msg.reset = true` drains silently (no output). `msg.complete` drains to the **expired** output. Don't conflate.
- Restart persistence requires `contextStorage` config in `settings.js` + the "Persist store" checkbox.
- v0.6 made `pathsToWait`/`pathsToExpire`/`useRegex` one-shot per-message overrides (breaking change from 0.5).

## node-red-contrib-postgresql (v0.15.4)

PostgreSQL query node with Mustache templating, numbered/named params, split-result streaming.

**Pitfalls:**
- **Triple-brace Mustache** (`{{{...}}}`) is unescaped — unsafe for untrusted input. Prefer numeric `$1`, `$2` params for SQL injection safety.
- Named params (`$id` + `msg.queryParameters.id`) are emulated, not native PG.
- With "Split results" + `rows per message = 1`, `msg.payload` is **the row object**, not an array.
- Streaming uses backpressure via `msg.tick`; node auto-detects downstream consumers via `node.tickConsumer`.

## node-red-contrib-actionflows (v2.1.2)

OOP-ish flow extensibility — late binding, prioritized overrides, conditional loops, scope (global/protected/private). Used in this codebase only for the `Act until observed` subflow's repeat-until-condition pattern.

**Pitfalls:**
- Matching is by name prefix (`Sample` → `Sample in`, `Sample_x`, `sample.y`). Use `protected`/`private` scope to avoid collisions.
- Priority is 1–99 (lower runs first); equal priorities fall back to creation order (fragile).
- Subflow name changes may require a Full Deploy to refresh the internal action map.
- `#deployed`-prefixed `action in` names fire automatically at deploy — easy to trigger by accident.

## node-red-contrib-bool-gate (v1.0.2)

Two nodes (`and`, `or`) that evaluate rules across recent messages and gate output via AND/NAND/OR/NOR/XOR/XNOR.

**Pitfalls:**
- Rules match by `topic` + property — every input must have a unique `msg.topic`.
- "True restriction" suppresses output on false results — easy to forget.

## node-red-contrib-boolean-logic-ultimate (v1.2.11)

Suite of boolean/utility nodes with persistent values and HA string→bool translation. Registers: `BooleanLogicUltimate`, `InvertUltimate`, `FilterUltimate`, `InterruptFlowUltimate`, `BlinkerUltimate`, `SimpleOutputUltimate`, `InjectUltimate`, `StatusUltimate`, `ImpulseUltimate`, `SumUltimate`, `toggleUltimate`, `RailwaySwitchUltimate`, `Comparator`, `KalmanFilterUltimate`, `RateLimiterUltimate`, `PresenceSimulatorUltimate`, `StaircaseLightUltimate`, `HysteresisUltimate`, `DebouncerUltimate`, `translator-config`.

**Pitfalls:**
- `BooleanLogicUltimate` expects N distinct topics. Reusing `msg.topic` resets state.
- Editing config clears retained values even with "Remember latest input values" on.
- `BlinkerUltimate` has separate stop-state config per output — easy to mismatch.
- `ImpulseUltimate` runs `send:`/`wait:ms` scripts; `msg.payload=false` aborts.
- No NAND/NOR — chain `InvertUltimate` after AND/OR.

## node-red-contrib-simple-gate (v0.5.2)

Single `gate` node with open/close control. **Messages while closed are DROPPED, not queued.**

**Pitfalls:**
- Use `node-red-contrib-queue-gate` if you need queued behavior.
- Control topic matched against the config; choose a unique topic to avoid stomping unrelated control flows.
- State persistence requires non-volatile context store + the "Restore from state saved in" checkbox.

## node-red-contrib-collector (v0.0.1)

Collects `topic`/`payload` pairs and emits an object with every topic seen so far.

**Pitfalls:**
- Msg with topic but no payload **deletes** that topic from the collector.
- Alpha versioned (0.0.1); state is in-memory, resets on redeploy.

## node-red-contrib-loop (v1.0.1)

Single `loop` node: fixed-count, condition-based, or enumeration over Array/Object/Map/Set/String/TypedArray. Two outputs: end-of-loop, step-of-loop.

**Pitfalls:**
- You must **manually wire output 2 (step) back to the input** through your processing nodes — looping is not automatic.
- `msg.command = "break"` / `"restart"` controls from inside the body.
- `msg.limit` is wall-clock cap in milliseconds.

## node-red-contrib-pid-controller-isa (v0.3.2)

Industrial PID with anti-windup, bumpless transfer, feed-forward, cascade tracking.

**Pitfalls:**
- `Ti` and `Td` in **seconds**, not minutes. `Ti=60` means 60s integral.
- `Ti=0` disables integral entirely.
- Reverse-acting flips error sign — required for cooling; direct mode on a chiller runs away.
- Setpoint changes via `msg.setpoint` are sticky until `msg.reset=true`.
- Cascade requires wiring `msg.trackingValue` from inner output back into outer node.

## node-red-contrib-prometheus-exporter (v1.0.5)

Exposes counters/gauges over Node-RED's HTTP port at `/metrics`.

**Pitfalls:**
- Only Counter and Gauge (no Histogram/Summary).
- Endpoint path is global (env var `PROMETHEUS_METRICS_PATH`).
- Labels must be pre-declared in the metric config; undeclared labels silently fail.

## node-threshold-control (v0.1.1)

Hysteresis threshold with on/off thresholds and delays. Three outputs: state, on-counter, off-counter.

**Pitfalls:**
- Delays in **seconds, rounded to integer** — fractional seconds lost.
- On threshold must be **higher** than off threshold (no validation).
- Initial state is `unknown` if first value is in the hysteresis band.
- Runtime overrides via `msg.onThreshold`, `msg.offThreshold`, `msg.onDelay`, `msg.offDelay`.

## @gregoriusrippenstein/node-red-contrib-introspection (v0.11.4)

Editor-only nodes for visual linting and flow introspection (Orphans, Link Calls, Undocumented, Obfuscate, Message Tracing, Screenshot/SVG export).

**Pitfalls:**
- **`sendflow` REPLACES all existing flows on the target** — destructive.
- "Clamp mode" tracing has no rate limit; can flood the editor.

## @inductiv/node-red-openai-api (v6.37.0)

Single `openai` node wrapping the OpenAI Node SDK v6.37. Works with OpenAI-compatible providers via custom `API Base`.

**Pitfalls:**
- **v6.34.0 breaking change:** `Create Conversation Item` requires `msg.payload.items` as an **array**. Singular `msg.payload.item` no longer matches.
- API key best stored as `cred` (encrypted in flows_cred.json).
- Output overwrites `msg.payload`.

## node-red-debugger (v1.1.1)

Plugin (NOT a node) — adds breakpoints/pause/step in the runtime via the sidebar.

**Pitfalls:**
- Disabled by default — toggle on in the sidebar.
- Subflow output breakpoints ignored.
- Pausing the runtime pauses everything, not just the flow you're inspecting.

## node-red-node-email (v5.2.3)

SMTP send + IMAP/POP3 receive. OAuth2 supported (required for Exchange/Outlook 365).

**Pitfalls:**
- v4.x → v5.x: re-enter credentials (internal property clash from upgrade).
- Office 365 requires OAuth2, not basic auth.
- Binary `msg.payload` auto-converts to attachment with `msg.filename`.

## node-red-node-ping (v0.3.3)

ICMP ping. Returns trip time (ms), or **`false`** on failure (boolean — downstream `msg.payload > 0` silently gets `false`).

**Pitfalls:**
- Permissions can bite on snap/raspbian — `sudo setcap cap_net_raw=ep /bin/ping` if needed.
- Default timed mode is 20s; cannot go below 1s.

## node-red-node-prowl (v0.0.10)

Push iOS notifications via Prowl. Title from `msg.topic` (NOT `msg.title`). Last published 2018 — consider Pushover or HA Mobile for new work.

**Pitfalls:**
- `msg.priority` range is **-2 to 2**, not 0-100.
- `msg.url` overrides static config — easy to leak unintended links if you reuse the payload object.
