# Draft upstream report: malformed inline source-map match aborts Vitest

Status: **draft only; not posted by this repository change**. Existing upstream issue [vitest-dev/vitest#10892](https://github.com/vitest-dev/vitest/issues/10892) and fix [vitest-dev/vitest#10893](https://github.com/vitest-dev/vitest/pull/10893) describe the same defect. This report retains the independent Pi/Nix reproduction and exact evidence.

## Environment

- `pi-coding-agent` 0.84.3 and 0.84.4
- Vitest and `@vitest/utils` 4.1.9
- `convert-source-map` 2.0.0
- `tsx` 4.22.1
- Node.js 24
- Nix sandbox on `aarch64-linux`; also reproduced directly on Darwin

## Observed failure

A 577-test run completed 574 tests successfully and skipped two, but exited nonzero with one unhandled error:

```text
SyntaxError: Unexpected token '�', "�" is not valid JSON
 ❯ new Converter node_modules/convert-source-map/index.js:83:15
 ❯ Object.exports.fromComment node_modules/convert-source-map/index.js:181:10
 ❯ Object.exports.fromSource node_modules/convert-source-map/index.js:207:22
 ❯ extractSourcemapFromFile node_modules/@vitest/utils/dist/source-map/node.js:8:32
 ❯ Object.getSourceMap node_modules/vitest/dist/chunks/cli-api.24X8XwN1.js:12636:102
 ❯ node_modules/@vitest/utils/dist/source-map.js:391:37
 ❯ parseStacktrace node_modules/@vitest/utils/dist/source-map.js:387:16
 ❯ parseErrorStacktrace node_modules/@vitest/utils/dist/source-map.js:438:51

 Test Files  1 failed | 36 passed (37)
      Tests  574 passed | 2 skipped (577)
     Errors  1 error
```

Full retained excerpt: [`evidence/pi-vitest-sourcemap/baseline-failure.log`](evidence/pi-vitest-sourcemap/baseline-failure.log).

## Offending file and bytes

Instrumentation around `extractSourcemapFromFile` identified:

```text
/build/source/node_modules/tsx/dist/register-B4MtRGQg.cjs
```

The exact `tsx@4.22.1` npm tarball integrity is:

```text
sha512-TvncJykhxAzFCk0VQZKBTClall4Pm7qXDSodb6uxi8QFa8X8mT6ABjxxsQ2opDRYxG7AzcRWXaFtruz5HJKuWg==
```

`register-B4MtRGQg.cjs` is 36,299 bytes, has SHA-256 `1710aefd9b856e256216166c7bf3c378249f696bccf367b80865e064b055494f`, and contains the sole marker at byte offset 29,191. It is source text, not a binary fixture. The marker appears inside a template-string constant used by `tsx` to generate source maps:

```js
hn=`
//# sourceMappingURL=data:application/json;base64,`,st=/* ... */
```

`convert-source-map` treats the remainder of that physical line as a base64 payload, decodes unrelated minified source bytes, and passes them to `JSON.parse`. Exact escaped and hexadecimal bytes are retained in [`instrumented-failure.log`](evidence/pi-vitest-sourcemap/instrumented-failure.log).

## Why Vitest reads this file

The underlying concurrent-session test error contained a `tsx` loader frame. Vitest formats that error through `parseErrorStacktrace`, which calls `parseStacktrace`, `getSourceMap`, and then `extractSourcemapFromFile` for each frame. Source-map extraction occurs while formatting the original error. The malformed false match throws first, so the reporter surfaces only Vitest/`convert-source-map` frames and hides the originating error.

The originating error was independently made deterministic: one process observed a half-initialized SQLite source-lock database and threw `Refusing unrecognized session lock database`. The vulnerable fork failed that regression 5/5 times; the transaction fix passed it 10/10 times. Both outputs are in [`baseline-failure.log`](evidence/pi-vitest-sourcemap/baseline-failure.log).

## Minimal reproduction

From an empty directory:

```sh
npm init -y
npm install --ignore-scripts @vitest/utils@4.1.9 tsx@4.22.1
node /path/to/doc/evidence/pi-vitest-sourcemap/repro.mjs
```

Unpatched output and status:

```text
THROWS register-B4MtRGQg.cjs -> SyntaxError: Unexpected token '�', "�" is not valid JSON
THROWS register-HCiphi1e.mjs -> SyntaxError: Unexpected token '�', "�" is not valid JSON
exit status: 1
```

With #10893 applied, output becomes:

```text
NO_THROW register-B4MtRGQg.cjs result=undefined
NO_THROW register-HCiphi1e.mjs result=undefined
exit status: 0
```

The Nix package also checks that a valid inline map still parses to `{ map }`, preventing a broad “disable source maps” workaround.

## Expected behavior and fix

Source maps are optional diagnostic metadata. A malformed or false-positive match should behave like no source map rather than abort error reporting:

```js
function extractSourcemapFromFile(code, filePath) {
  try {
    const map = (convertSourceMap.fromSource(code)
      || convertSourceMap.fromMapFileSource(code, createConvertSourceMapReadMap(filePath)))?.toObject();
    return map ? { map } : undefined;
  } catch {
    return undefined;
  }
}
```

This is the behavior backported from #10893. The blocking package gate remains enabled and runs the fork's complete credential-isolated non-e2e suite.

## Verification evidence

Commands, exact test accounting, derivation paths, repository gates, and non-activation proof are retained in [`verification.log`](evidence/pi-vitest-sourcemap/verification.log).
