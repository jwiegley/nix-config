# Node-RED admin helper reference

## Contents

- [Trust boundary](#trust-boundary)
- [Complete command allowlist](#complete-command-allowlist)
- [Envelope and concurrency contract](#envelope-and-concurrency-contract)
- [Limits, exits, and errors](#limits-exits-and-errors)
- [Private fetch-edit-put workflow](#private-fetch-edit-put-workflow)

## Trust boundary

`node-red-admin` is for a trusted, authorized Node-RED flow author. This means
the caller may inspect and edit the selected flow. The helper keeps its runtime
admin transport credential out of routine agent handling; it is not an
operating-system sandbox or a defense against intentionally malicious flow
code.

A selected flow is authorized but sensitive output, not "non-secret data." It
may contain private configuration even though the helper never fetches a
separate credential store. Keep returned JSON out of the conversation, logs,
command arguments, shared directories, and long-lived files.

The helper owns a fixed loopback route and verifies the TLS identity of
`nodered.vulcan.lan`. Callers cannot choose a method, path, URL, host, or
transport option. Never bypass it with a network client, language HTTP library,
direct flow-file access, or a credential read.

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

## Envelope and concurrency contract

All successful output is compact ASCII JSON followed by one LF, with no headers
or commentary.

- `flows get` returns tab metadata only:
  `{"flows":[{"id":"a1b2c3d4","label":"Office"}]}`.
- `flow get` returns exactly
  `{"baseDigest":"sha256:<64 lowercase hex>","flow":<complete selected flow>}`
  with key order `baseDigest`, then `flow`.
- `flow put` requires exactly those two top-level keys, with no extras. Edit only
  `flow`; preserve `baseDigest`. The flow ID must equal `FLOW_ID`, `nodes` must
  be an array, and `configs`, when present, must be an array.

`baseDigest` is the SHA-256 of strict canonical JSON bytes for the decoded flow:
ASCII escapes, recursively sorted object keys, compact separators, and no NaN,
infinity, duplicate keys, or excessive nesting. Do not recompute it after an
edit: it identifies the version that was fetched, not the edited flow.

After fully validating input, `flow put` re-fetches the selected flow and
compares its fresh digest immediately before updating. A mismatch sends no PUT,
exits 1, and reports exactly `node-red-admin: selected flow changed; fetch again`.
The helper sends only `flow`, never the envelope, digest, or credential.

`scripts/validate_flow.py` additionally applies skill-side authoring checks to
node IDs, containers, and wires. Those checks are policy for safe edits, not a
claim that the helper enforces every Node-RED semantic relationship.

Upstream status 200 is accepted only with a strict JSON object containing the
matching ID; status 204 is accepted only with an empty body. Caller success is
exactly `{"ok":true,"id":"FLOW_ID"}` followed by LF.

## Limits, exits, and errors

Raw and normalized PUT input are each limited to 1 MiB. A returned envelope and
all final stdout are limited to 1 MiB including LF. Each upstream body is
limited to 8 MiB.

The 10-second timeout applies to each network I/O operation. One non-rearmed
15-second wall deadline bounds the whole lifecycle, including stdin processing
and stdout/stderr flushing.

- 0: success.
- 2: invalid command, ID, envelope, input shape, ID mismatch, or input size.
- 1: credential, stale digest, transport, upstream, response, timeout, or other
  operational failure.

Ordinary failures write fixed, bounded diagnostics prefixed with
`node-red-admin:`. They never echo request data, upstream bodies, exception
text, or the transport credential. Usage is appended only for exit-2 failures.
A hard wall-deadline expiry may be silent.

## Private fetch-edit-put workflow

Run this from the skill directory. The first command makes every later failure
terminal. The exact acknowledgement check must pass before the final fetch.

```bash
set -euo pipefail
umask 077
workdir="$(mktemp -d "${TMPDIR:-/tmp}/node-red-admin.XXXXXX")"
cleanup() { rm -rf -- "$workdir"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 700 "$workdir"

flow_id=a1b2c3d4
node-red-admin flows get > "$workdir/flows.json"
node-red-admin flow get "$flow_id" > "$workdir/before-envelope.json"
cp "$workdir/before-envelope.json" "$workdir/updated-envelope.json"
# Edit only .flow in updated-envelope.json; preserve .baseDigest unchanged.
python3 scripts/validate_flow.py "$workdir/updated-envelope.json" > "$workdir/validation.txt"
node-red-admin flow put "$flow_id" < "$workdir/updated-envelope.json" > "$workdir/ack.json"
printf '{"ok":true,"id":"%s"}\n' "$flow_id" > "$workdir/expected-ack.json"
cmp -s "$workdir/expected-ack.json" "$workdir/ack.json"
node-red-admin flow get "$flow_id" > "$workdir/after-envelope.json"
python3 scripts/validate_flow.py "$workdir/after-envelope.json" > "$workdir/after-validation.txt"
```

Compare the before/after envelopes without emitting their contents. Stop and
report any failure; never switch to a lower-level transport or runtime file.
