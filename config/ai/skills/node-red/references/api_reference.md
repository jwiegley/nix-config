# Node-RED admin helper reference

## Trust boundary

`node-red-admin` is for a trusted, authorized Node-RED flow author. It keeps
the runtime admin transport credential out of routine agent handling. It is not
an operating-system sandbox, a privilege boundary against an already privileged
user, or a defense against intentionally malicious flow code.

A selected flow is authorized but sensitive output. It may contain private
configuration even though the helper never fetches the separate credential
store. Keep returned JSON out of the conversation, logs, command arguments,
shared directories, and long-lived files.

The helper owns a fixed loopback route and verifies the TLS identity of
`nodered.vulcan.lan`. Callers cannot choose a method, path, URL, host, or
transport option. Never bypass the helper with a network client, language HTTP
library, direct flow-file access, or a credential read.

## Complete command allowlist

These three signatures are the entire caller interface:

```text
node-red-admin flows get
node-red-admin flow get FLOW_ID
node-red-admin flow put FLOW_ID < flow.json
```

Do not add privilege escalation, options, extra arguments, create/delete verbs,
or whole-configuration operations. `-h` and `--help` are invalid and exit 2.
`flow put` accepts JSON only on standard input; a filename is not an argument.

`FLOW_ID` must entirely match
`[0-9a-f]{1,32}(?:\.[0-9a-f]{1,32})?\Z`: one or two lowercase hexadecimal
segments of 1-32 characters, separated by at most one dot.

## Output contract

All successful output is compact ASCII JSON followed by one LF, with no headers
or commentary.

- `flows get` returns tab metadata only:
  `{"flows":[{"id":"a1b2c3d4","label":"Office"}]}`.
- `flow get` returns the complete selected-flow object, normalized without field loss.
  The returned ID must equal `FLOW_ID`. The helper refuses output that contains
  its own transport credential.
- `flow put` requires a JSON object whose `id` equals `FLOW_ID`. Only upstream
  success status 200 or 204 is accepted. Its acknowledgement has exact key
  order: `{"ok":true,"id":"FLOW_ID"}`.

The raw input and its normalized JSON form must each be at most 1 MiB. An
upstream response may be at most 8 MiB. Final stdout, including LF, may be at
most 1 MiB.

Each I/O operation has a 10-second timeout. A 15-second wall deadline covers
parsing, standard input, network work, and stdout/stderr flushing for the whole
valid operation.

## Exit and error contract

- 0: success.
- 2: invalid command, ID, input shape, ID mismatch, or input size.
- 1: credential, transport, upstream, response, timeout, or other operational
  failure.

Ordinary failures write only fixed, bounded diagnostics prefixed with
`node-red-admin:`. They do not echo request data, upstream bodies, exception
text, or the transport credential. Usage is appended only for exit-2 failures.
If the wall deadline expires while reporting, the helper may exit silently; it
uses status 1 for an operation timeout and preserves status 2 for an already
classified caller error.

## Private fetch-edit-put workflow

Use a fresh mode-0700 directory, restrictive umask, and cleanup trap. Redirect
every response to that directory; do not inspect flow JSON through a tool that
will surface it in the conversation.

```bash
umask 077
workdir="$(mktemp -d "${TMPDIR:-/tmp}/node-red-admin.XXXXXX")"
chmod 700 -- "$workdir"
cleanup() { rm -rf -- "$workdir"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

flow_id=a1b2c3d4
node-red-admin flows get > "$workdir/flows.json"
node-red-admin flow get "$flow_id" > "$workdir/before.json"
cp -- "$workdir/before.json" "$workdir/updated.json"
# Edit only the requested fields in updated.json, preserving every other field.
node-red-admin flow put "$flow_id" < "$workdir/updated.json" > "$workdir/ack.json"
node-red-admin flow get "$flow_id" > "$workdir/after.json"
```

Validate the edit locally, confirm the fixed acknowledgement, and compare the
before/after documents without emitting their contents. Stop and report a
helper error; never switch to a lower-level transport or direct runtime file.
