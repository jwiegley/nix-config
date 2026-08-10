{
  bun,
  runCommand,
  sourceForChecks,
}:

# Runs each test/ai/extensions/*/index.test.ts. Discovery, not a
# hand-maintained list: a new extension's suite runs the moment its
# index.test.ts exists (only that filename, exactly one level deep). The
# floor catches a suite being deleted or renamed; a glob matching nothing
# already aborts under set -eu.
runCommand "pi-extension-tests" { nativeBuildInputs = [ bun ]; } ''
  set -euo pipefail

  ran=0
  for suite in ${sourceForChecks}/test/ai/extensions/*/index.test.ts; do
    (
      cd "$(dirname "$suite")"
      bun test index.test.ts
    )
    ran=$((ran + 1))
  done
  [ "$ran" -ge 2 ] || {
    echo "pi-extension-tests: expected at least 2 extension suites, ran $ran" >&2
    exit 1
  }

  mkdir -p "$out"
  touch "$out/passed"
''
