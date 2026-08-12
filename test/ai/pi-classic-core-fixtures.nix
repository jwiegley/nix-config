{
  classicPackage,
  coreutils,
  nodejs_24,
  runCommand,
}:

runCommand "pi-classic-core-fixtures-v1"
  {
    nativeBuildInputs = [ nodejs_24 ];
  }
  ''
    set -euo pipefail
    umask 077

    mkdir -p "$out/identity" "$out/protocol" "$out/tools" "$out/fixtures"
    cp ${classicPackage}/b1-source-identity.json "$out/identity/source.json"
    cp ${classicPackage}/b1-source-crosswalk.json "$out/identity/source-to-runtime-crosswalk.json"
    cp ${classicPackage}/empty-extensions.json "$out/identity/empty-extensions.json"

    cp ${./pi-bounded-memory/fixture-spec-v1.json} "$out/protocol/fixture-spec-v1.json"
    cp ${./pi-bounded-memory/operations-v1.json} "$out/protocol/operations-v1.json"
    cp ${./pi-bounded-memory/common.mjs} "$out/tools/common.mjs"
    cp ${./pi-bounded-memory/generate-fixtures.mjs} "$out/tools/generate-fixtures.mjs"
    cp ${./pi-bounded-memory/reference-oracle.mjs} "$out/tools/reference-oracle.mjs"
    cp ${./pi-bounded-memory/classic-core-diagnostic.mjs} "$out/tools/classic-core-diagnostic.mjs"
    cp ${./pi-bounded-memory/run-capped-command.mjs} "$out/tools/run-capped-command.mjs"
    cp ${./pi-bounded-memory/record-postflight.mjs} "$out/tools/record-postflight.mjs"
    cp ${./pi-bounded-memory/summarize-diagnostic.mjs} "$out/tools/summarize-diagnostic.mjs"
    cp ${./pi-bounded-memory/seal-bundle.mjs} "$out/tools/seal-bundle.mjs"
    cp ${./pi-bounded-memory/README.md} "$out/tools/README.md"

    node "$out/tools/generate-fixtures.mjs" \
      --spec "$out/protocol/fixture-spec-v1.json" \
      --fixtures "$out/fixtures" \
      --output "$out/fixtures/generation.json"

    node "$out/tools/reference-oracle.mjs" \
      --spec "$out/protocol/fixture-spec-v1.json" \
      --fixtures "$out/fixtures" \
      --generation "$out/fixtures/generation.json" \
      --operations "$out/protocol/operations-v1.json" \
      --generator "$out/tools/generate-fixtures.mjs" \
      --reference "$out/tools/reference-oracle.mjs" \
      --diagnostic "$out/tools/classic-core-diagnostic.mjs" \
      --source-identity "$out/identity/source.json" \
      --crosswalk "$out/identity/source-to-runtime-crosswalk.json" \
      --empty-extensions "$out/identity/empty-extensions.json" \
      --manifest "$out/fixtures/manifest.json" \
      --oracles "$out/fixtures/expected-oracles.json"

    node --input-type=module --eval '
      import assert from "node:assert/strict";
      import { pathToFileURL } from "node:url";
      const { streamJsonLines } = await import(pathToFileURL(process.argv[1]));
      assert.throws(
        () => streamJsonLines(process.argv[2], { chunkBytes: 8, maxLineBytes: 8 }, () => {}),
        { message: "retained fold factory is required" },
      );
    ' "$out/tools/common.mjs" "$TMPDIR/missing-fold-probe.jsonl"

    postflight_fixture="$TMPDIR/pi-b1-postflight.jsonl"
    invalid_postflight="$TMPDIR/pi-b1-invalid-postflight.json"
    ${coreutils}/bin/cp --reflink=never \
      "$out/fixtures/pi-b1-16m.jsonl" "$postflight_fixture"
    chmod 0600 "$postflight_fixture"
    if node "$out/tools/record-postflight.mjs" \
      --fixture "$postflight_fixture" \
      --result "$TMPDIR/missing-result.json" \
      --run-result "$TMPDIR/missing-run-result.json" \
      --oracles "$out/fixtures/expected-oracles.json" \
      --endpoint 16m \
      --copy-executable ${coreutils}/bin/cp \
      --output "$invalid_postflight"; then
      echo "failed postflight unexpectedly exited successfully" >&2
      exit 1
    fi
    node --input-type=module --eval '
      import { readFileSync } from "node:fs";
      const record = JSON.parse(readFileSync(process.argv[1], "utf8"));
      if (
        record.success !== false ||
        record.checks?.all !== false ||
        record.checks?.resultPresent !== false ||
        record.checks?.runResultPresent !== false
      ) {
        throw new Error("failed postflight evidence was not preserved");
      }
    ' "$invalid_postflight"

    success_result="$TMPDIR/pi-b1-success-result.json"
    success_run_result="$TMPDIR/pi-b1-success-run-result.json"
    success_stderr="$TMPDIR/pi-b1-success-stderr.log"
    success_postflight="$TMPDIR/pi-b1-success-postflight.json"
    node "$out/tools/run-capped-command.mjs" \
      --stdout "$success_result" \
      --stderr "$success_stderr" \
      --run-result "$success_run_result" \
      --max-bytes 16777216 \
      -- \
      node --input-type=module --eval '
        import { appendFileSync, readFileSync } from "node:fs";
        import { pathToFileURL } from "node:url";
        const { structuredSha256 } = await import(pathToFileURL(process.argv[1]));
        const oracles = JSON.parse(readFileSync(process.argv[2], "utf8"));
        const fixturePath = process.argv[3];
        const oracle = oracles.fixtures["16m"];
        const userEntryId = "postflight-success-user-v1";
        const assistantEntryId = "postflight-success-assistant-v1";
        const entries = [
          {
            type: "message",
            id: userEntryId,
            parentId: oracle.before.activeLeaf.id,
            message: oracles.continuation.userMessage,
          },
          {
            type: "message",
            id: assistantEntryId,
            parentId: userEntryId,
            message: oracles.continuation.assistantMessage,
          },
        ];
        appendFileSync(fixturePath, entries.map((entry) => JSON.stringify(entry)).join("\n") + "\n");
        process.stdout.write(JSON.stringify({
          schema: 1,
          kind: "pi-b1-classic-core-diagnostic",
          qualification: "descriptive-b1-only",
          endpoint: "16m",
          checks: { all: true },
          process: { environmentSha256: structuredSha256(process.env) },
          identities: {
            fixture: {
              expectedCanonicalBytes: oracle.canonical.bytes,
              expectedCanonicalSha256: oracle.canonical.sha256,
            },
          },
          continuation: {
            userEntryId,
            assistantEntryId,
            priorLeafId: oracle.before.activeLeaf.id,
            userMessageSha256: oracles.continuation.userMessageSha256,
            assistantMessageSha256: oracles.continuation.assistantMessageSha256,
          },
        }) + "\n");
      ' \
        "$out/tools/common.mjs" \
        "$out/fixtures/expected-oracles.json" \
        "$postflight_fixture"
    node "$out/tools/record-postflight.mjs" \
      --fixture "$postflight_fixture" \
      --result "$success_result" \
      --run-result "$success_run_result" \
      --oracles "$out/fixtures/expected-oracles.json" \
      --endpoint 16m \
      --copy-executable ${coreutils}/bin/cp \
      --output "$success_postflight"
    node --input-type=module --eval '
      import { readFileSync } from "node:fs";
      const record = JSON.parse(readFileSync(process.argv[1], "utf8"));
      if (record.success !== true || record.checks?.all !== true) {
        throw new Error("successful postflight evidence was not preserved");
      }
    ' "$success_postflight"

    node "$out/tools/seal-bundle.mjs" --root "$out"
  ''
