# Pi classic B1 fixture tools

This is a standalone Node-standard-library bundle for candidate-independent Pi
classic-core B1 evidence. B1 is descriptive only. It is never M1 or M2
qualification, and no tool in this bundle makes a 32 MiB verdict.

## Fixture and reference

`fixture-spec-v1.json` fixes Pi session version 3, public seed, timestamps, IDs,
and four bulk counts: 512, 2,048, 8,192, and 32,768. Every bulk user-message
record is exactly 32,768 bytes including its LF, and the first N bulk records
are byte-identical at every larger scale. A fixed header and root precede the
bulk chain. The 13-entry tail contains model and thinking changes, a two-way
branch, extension snapshot, left-branch label, kept pair, compaction, and
post-compaction pair. Only the first tail parent is scale-specific.

Structured digests are SHA-256 over recursively UTF-8-byte-key-sorted compact
JSON. Folds prefix each structured record with an unsigned big-endian 64-bit
length. Exact stream hashes cover raw bytes. `operations-v1.json` has the exact
nonempty unique roster `classic-open`, `active-context-before`,
`bounded-point-diagnostics`, `fixed-continuation`, and `retained-ready`.
The reference exact-compares every field of all five rows. Per fixture it also
records the observed open counts/raw bytes and the canonical UTF-8 byte lengths
of the five-message active context, 16 point descriptors whose hashes bind the
label/snapshot values and branch edges, and the two continuation messages plus
their resulting active context. It enforces the three finite item/byte caps.
The single retained-ready sample is enforced by the diagnostic summary;
classic open is recorded but intentionally remains the unbounded O(history)
baseline.

Generate canonical mode-0444 fixtures and a generation record:

```sh
node generate-fixtures.mjs \
  --spec fixture-spec-v1.json --fixtures FIXTURES --output generation.json
```

Create the candidate-independent manifest and oracles. This command imports no
Pi module and consumes no candidate result:

```sh
node reference-oracle.mjs \
  --spec fixture-spec-v1.json --fixtures FIXTURES \
  --generation generation.json --operations operations-v1.json \
  --generator generate-fixtures.mjs --reference reference-oracle.mjs \
  --diagnostic classic-core-diagnostic.mjs \
  --source-identity b1-source-identity.json \
  --crosswalk b1-source-crosswalk.json \
  --empty-extensions empty-extensions.json \
  --manifest manifest.json --oracles oracles.json
```

Every bundle-owned output uses exclusive temporary creation followed by an
exclusive hard-link publication. Existing targets are never replaced.

## Fresh-copy diagnostic

The external runner must use its exact Nix-store GNU coreutils `cp` executable
with `--reflink=never`, creating `namespace:session.jsonl` at mode 0600. The
normalized custody argv is:

```text
cp --reflink=never fixture:<endpoint> namespace:session.jsonl
```

The exact `${coreutils}/bin/cp` launcher is an in-store symlink. Postflight
records its literal bounded link target and store output, resolves it, and
hashes the resolved regular coreutils executable. The manifest deliberately
makes no claim about opaque GNU `cp` chunk size,
in-flight buffers, or descriptor internals. Postflight records the bounded
executable file identity and store output, mode 0600, and full canonical-prefix
bytes/SHA-256. The sealed runner hash is the exact invocation authority.

Run the child only on that fresh writable copy. The extension manifest must
parse as exactly `{"extensions":[]}`.

```sh
node --expose-gc classic-core-diagnostic.mjs \
  --package-root ROOT --fixture COPY --manifest manifest.json \
  --oracles oracles.json --extension-manifest empty-extensions.json \
  --endpoint 16m
```

Before importing Pi, the child performs only constant-space `lstat`, exact-size,
and at-most-4,096-byte header checks against the immutable oracle. It does not
hash, stream, parse, or fold the full fixture. It imports only classic
`session-manager.js`, opens the session, addresses at most 16 distinct fixed IDs,
builds and checks both active contexts, appends exactly one fixed user and one
fixed assistant message, and reaches one retained-ready sample after three
GC-plus-`setImmediate` turns with the manager still open. It never calls
`getEntries`, `getTree`, or a diagnostic-owned history scan.

Cap both child streams at the frozen 16,777,216 bytes. The runner uses no shell,
reserves its run-result temporary before starting the child, and rejects every
collision among final and derived-temporary output paths. Signal handling spans
sink setup through final publication. The child runs in a dedicated POSIX
process group; overflow, I/O errors, and parent signals terminate the group, and
leader exit also kills descendants before awaiting pipe close. The runner
records bounded nested stdout/stderr identities plus safe concrete argv and a
separate environment digest, then writes its no-clobber result before returning
the child-derived outcome.

```sh
node run-capped-command.mjs \
  --stdout result.json --stderr diagnostic.stderr \
  --run-result run-result.json --max-bytes 16777216 -- \
  node --expose-gc classic-core-diagnostic.mjs ...
```

After the child, stream the disposable fixture and bind the small files using
single-read JSON identities. Canonical bytes and SHA-256 come from immutable
oracles even when the child result is absent or invalid.

```sh
node record-postflight.mjs \
  --fixture COPY --result result.json --run-result run-result.json \
  --oracles oracles.json --endpoint 16m \
  --copy-executable /nix/store/HASH-coreutils-VERSION/bin/cp \
  --output postflight.json
```

Summarize the low/high endpoints. The summary is always published and remains
useful when a semantic result is absent: it retains each valid postflight's
fixture, copy, runner, and oracle evidence. An endpoint succeeds only when its
run result, postflight, semantic result, hashes, raw RSS schema/units, one-sample
retained barrier, and counts all validate. Completion additionally requires
equal low/high manifest, oracle, source/package, runtime, extension, tool, copy,
and normalized command/environment identities. It retains raw memory/resource
values and reports signed high-minus-low RSS and count deltas.

```sh
node summarize-diagnostic.mjs \
  --low low-result.json --low-postflight low-postflight.json \
  --high high-result.json --high-postflight high-postflight.json \
  --output summary.json
```

Finally seal the external result root. The outer runner may publish the sealed
bundle and then exit nonzero for a failed endpoint, so failure evidence remains.

```sh
node seal-bundle.mjs --root BUNDLE
```

The seal rejects symlinks and non-regular entries, bytewise-sorts relative
paths, hashes every regular file except root `SHA256SUMS`, and publishes an
LF-terminated checksum file without replacement.

## Frozen bounds

- Generation retains one scale-dependent bulk entry record and one open fixture
  descriptor. The fixed root and 13-entry tail templates are non-scale schema
  descriptors and are not counted as streamed bulk records.
- Reference import uses 32,768-byte lines, 65,536-byte chunks, and one fixture
  descriptor. It holds at most 64 entry and point-descriptor objects (52
  observed for this schema). Separately, `scaleResults` holds at most four
  fixed-schema scale-result oracle graphs, including the current graph under
  construction. A parsed record and its independently expected record account
  for two concurrent logical representations and at most 65,536 serialized
  bytes; this is a logical-record bound, not a JavaScript heap-size claim.
- Diagnostic preflight reads at most 4,096 fixture bytes and retains at most 16
  distinct fixed point IDs. It performs no full-fixture identity pass inside
  the RSS child.
- Postflight uses one open file, 65,536-byte hash chunks, a 1,048,576-byte
  retained suffix cap, 1,024-byte copy-launcher target cap, 16,777,216-byte JSON
  cap, and 16,777,216-byte resolved copy-executable identity cap. Full-prefix
  hashing is external to the RSS child.
- Capped command output is exactly 16,777,216 bytes per stream. Its concrete
  argv is capped at 64 arguments, 65,536 UTF-8 bytes including terminating NUL
  separators, and 4,096 encoded bytes per argument. It holds two sink files,
  two stream temporaries, and one closed run-result reservation, and uses a
  1,000 ms signal and descendant-pipe grace period.
- Seal caps are 512 total directory entries, 256 files, nine simultaneously
  open directories, depth 8, 1,024 bytes per relative path, 65,536 total
  relative-path bytes, and 131,072 checksum bytes; hash chunks are 65,536
  bytes.

The manifest records every generator, import, diagnostic, copy-policy,
postflight, capped-command, bundle-write, and seal bound, together with tool,
source/package, runtime, and empty-extension identities. The intentionally
eager classic `SessionManager` is the only O(history) retained component.
