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

    invalid_fixture="$TMPDIR/pi-b1-invalid-postflight.jsonl"
    invalid_postflight="$TMPDIR/pi-b1-invalid-postflight.json"
    ${coreutils}/bin/cp --reflink=never \
      "$out/fixtures/pi-b1-16m.jsonl" "$invalid_fixture"
    chmod 0600 "$invalid_fixture"
    if node "$out/tools/record-postflight.mjs" \
      --fixture "$invalid_fixture" \
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

    node "$out/tools/seal-bundle.mjs" --root "$out"
  ''
