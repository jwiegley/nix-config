# Node-RED event logging — vulcan

## What gets logged

**`msg_events`** is populated by the `node-red-event-logger` plugin (`/var/lib/node-red/node_modules/node-red-event-logger/index.js`) via `RED.hooks.add(...)`:
- `onSend` — every wire-level message dispatch (source node)
- `onComplete` — every node completion (includes `event.error` if present). The hook payload wraps node as `event.node.node`; the plugin unwraps it so `tab_id`/`node_type`/`node_name` are populated.

**`audit_events`** is populated by the `dbAudit` logging handler in `/etc/nixos/config/node-red-settings.js`. Captures Node-RED's audit stream: deploys, flow edits, palette installs, auth events, runtime errors.

**Retention:**
- `msg_events` is RANGE-partitioned by `ts` (monthly). Timer `node-red-event-logger-rotate.timer` fires daily at 03:30 running `rotate.sql`: creates next month's partition, drops partitions whose `p_start + 1 month < now() - 30 days`.
- `audit_events` trimmed in the same rotation: `DELETE FROM audit_events WHERE ts < now() - INTERVAL '90 days'`.

**Payload truncation:** `MAX_PAYLOAD_BYTES = 4096` (UTF-8 bytes). `payload_size` always records pre-truncation byte count. Oversize payloads become `{"_truncated": true, "preview": "<first ~4032 bytes>"}` (byte-aware truncation; partial multi-byte sequences become U+FFFD).

**Insert batching:** 200 ms flush interval, 500 rows/batch, 50,000-row in-memory cap (drops oldest on overflow).

## Database schema

Database `nodered_events`, schema `public`.

```
msg_events (PARTITION BY RANGE (ts))
  id           bigint       NOT NULL  DEFAULT nextval('msg_events_id_seq')
  ts           timestamptz  NOT NULL  DEFAULT now()
  hook         text         NOT NULL  -- 'onSend' | 'onComplete'
  msgid        text                   -- msg._msgid (chain ID)
  tab_id       text                   -- flow tab UUID
  node_id      text                   -- node UUID
  node_type    text                   -- e.g. 'function', 'api-call-service'
  node_name    text                   -- user-visible label
  topic        text                   -- msg.topic
  payload      jsonb                  -- truncated to 4KB
  payload_size integer                -- pre-truncation byte count
  error        text                   -- onComplete error message
Indexes: msg_events_ts_idx(ts), msg_events_msgid_idx(msgid), msg_events_node_idx(node_id)

audit_events
  id      bigint       PRIMARY KEY  DEFAULT nextval('audit_events_id_seq')
  ts      timestamptz  NOT NULL     DEFAULT now()
  level   integer                   -- Node-RED log level
  type    text                      -- e.g. 'flows', 'comms', 'auth'
  event   text                      -- e.g. 'flows.deploy', 'auth.login'
  name    text
  node_id text
  msg     text                      -- stringified message body
  "user"  text                      -- requesting username (reserved word)
Indexes: audit_events_pkey(id), audit_events_event_idx(event), audit_events_ts_idx(ts)
```

## Connection / permissions

```
postgres=arwdDxtm  (owner, full)
"node-red"=a       (INSERT only, no SELECT — write-only audit pattern)
grafana=r          (SELECT — used by the dashboard)
```

Default privileges in `public` grant the same to future monthly partitions automatically.

**Gotcha:** the `node-red` role cannot read `msg_events`. To inspect rows manually, connect as `postgres`:

```bash
sudo -u postgres psql -d nodered_events
```

Do NOT `sudo -u node-red psql ...` for reads — it errors on `SELECT`. Grafana queries work because the `grafana` role has SELECT.

## Useful queries

```sql
-- Trace one msgid through the chain (ordered)
SELECT ts, hook, node_type, node_name, topic, payload, error
FROM msg_events
WHERE msgid = 'abc123def456'
ORDER BY ts;

-- All fires of a node in last 24h
SELECT ts, hook, msgid, topic, payload
FROM msg_events
WHERE node_id = '<node-uuid>' AND ts > now() - INTERVAL '24 hours'
ORDER BY ts DESC;

-- Errors in last hour
SELECT ts, node_type, node_name, error, msgid
FROM msg_events
WHERE error IS NOT NULL AND ts > now() - INTERVAL '1 hour'
ORDER BY ts DESC;

-- Recent fires on a flow tab
SELECT ts, node_type, node_name, topic
FROM msg_events
WHERE tab_id = '<tab-uuid>' AND ts > now() - INTERVAL '1 hour'
ORDER BY ts DESC LIMIT 200;

-- Count distinct chains where a payload predicate held
SELECT count(DISTINCT msgid)
FROM msg_events
WHERE ts > now() - INTERVAL '24 hours'
  AND payload->>'state' = 'on';

-- Find onSend events from a specific tab where a sibling node fired between two times
SELECT ts, node_name, payload
FROM msg_events
WHERE tab_id = '<tab-uuid>' AND hook = 'onSend'
  AND ts BETWEEN '<from>' AND '<to>'
ORDER BY ts;
```

## Grafana dashboard

URL: `https://grafana.vulcan.lan/d/node-red-events`. Datasource UID `nodered_events`. Refresh 30s. Variable `$msgid` (textbox) drives the trace panel.

| Panel | What it shows | Query | When to use |
|---|---|---|---|
| **Events per minute** | timeseries, 1-min buckets of all `msg_events` rows | `SELECT $__timeGroup(ts,'1m') AS time, count(*) FROM msg_events WHERE $__timeFilter(ts) GROUP BY 1` | Spot traffic spikes / silence; confirm Node-RED is emitting |
| **All events (browseable)** | filterable table, last 2000 events in range | `SELECT ts, hook, node_type, node_name, topic, msgid, payload, payload_size, error FROM msg_events WHERE $__timeFilter(ts) ORDER BY ts DESC LIMIT 2000` | Primary exploration; use column filters; copy a msgid into `$msgid` |
| **Recent errors** | last 50 rows with `error IS NOT NULL` | `SELECT ts, node_type, node_name, error FROM msg_events WHERE error IS NOT NULL AND $__timeFilter(ts) ORDER BY ts DESC LIMIT 50` | Triage onComplete failures across the flow |
| **Message trace lookup** | ordered chain for `msgid = '$msgid'` | `SELECT ts, hook, node_type, node_name, topic, payload FROM msg_events WHERE msgid = '$msgid' ORDER BY ts` | After picking a msgid from the table: see full chain hop-by-hop |

## Debugging workflow

### "X didn't fire" — trigger node never emitted
```sql
SELECT ts, msgid, topic, payload
FROM msg_events
WHERE node_id = '<trigger-uuid>' AND hook = 'onSend'
  AND ts BETWEEN '<window-start>' AND '<window-end>'
ORDER BY ts;
```
- **Zero rows** → upstream never reached the trigger. Check the source node's `onSend` for the same window.
- **Rows present** → trigger fired but downstream halted. Pick the latest `msgid` and trace below.

### "X fired when it shouldn't"
1. Identify the offending action (Grafana panel "All events", filter by `node_name`, hook `onSend`).
2. Copy its `msgid` into `$msgid` (or query directly).
3. Trace backwards:
   ```sql
   SELECT ts, hook, node_type, node_name, topic, payload
   FROM msg_events WHERE msgid = '<msgid>' ORDER BY ts;
   ```
4. Walk top-to-bottom — the first row is the trigger; each subsequent `onSend` is a hop. Inspect `payload` at each hop to find the predicate that wrongly evaluated true.

### Chain across `link in`/`link out`
msgid is preserved across `link out → link in`. Across `split`/`join`, custom functions that build a new `msg`, or HA-WS triggers that re-emit, msgid may change — pivot on `ts` + `tab_id` + `topic` to bridge.

### "Why did this scheduled fire not happen?"
chronos-scheduler's `random` offset is re-rolled on every Node-RED restart. If a rolling deploy bumped the schedule past its window, the fire is silently lost. Check `audit_events` for deploys in the suspect window:
```sql
SELECT ts, event, "user", msg
FROM audit_events
WHERE event LIKE 'flows.%' AND ts > now() - INTERVAL '24 hours'
ORDER BY ts;
```

## Source files

- `/etc/nixos/config/node-red-event-logger/{schema.sql,rotate.sql,index.js,package.json}`
- `/etc/nixos/modules/services/node-red-event-logger.nix`
- `/etc/nixos/modules/monitoring/dashboards/node-red-events.json`
- `/etc/nixos/config/node-red-settings.js` (lines ~138–180: dbAudit handler)
