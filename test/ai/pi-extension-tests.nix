{
  bun,
  runCommand,
  sourceForChecks,
}:

# Runs each test/ai/extensions/*/index.test.ts. Discovery, not a
# hand-maintained list: a new extension's suite runs the moment its
# index.test.ts exists (only that filename, exactly one level deep). A glob
# matching nothing already aborts under set -eu.
runCommand "pi-extension-tests" { nativeBuildInputs = [ bun ]; } ''
  set -euo pipefail

  for suite in ${sourceForChecks}/test/ai/extensions/*/index.test.ts; do
    (
      cd "$(dirname "$suite")"
      bun test index.test.ts
    )
  done

  mkdir -p "$out"
  touch "$out/passed"
''
