#!/usr/bin/env node
import { createHash } from "node:crypto";
import { closeSync, constants, fstatSync, lstatSync, openSync, readlinkSync, readSync, realpathSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import {
  allBooleansTrue,
  check,
  exactJsonEqual,
  hashFile,
  isObject,
  parseArgs,
  readJson,
  structuredSha256,
  writeJsonAtomic,
} from "./common.mjs";

const args = parseArgs(process.argv.slice(2), [
  "fixture",
  "result",
  "run-result",
  "oracles",
  "endpoint",
  "copy-executable",
  "output",
]);

function safeJson(path, maxBytes) {
  const target = resolve(path);
  try {
    const input = readJson(target, maxBytes);
    return { path: target, present: true, valid: true, bytes: input.bytes, sha256: input.sha256, value: input.value };
  } catch (error) {
    const absent = error?.code === "ENOENT";
    return {
      path: target,
      present: !absent,
      valid: false,
      bytes: error?.identity?.bytes ?? null,
      sha256: error?.identity?.sha256 ?? null,
      error: absent ? "absent" : "invalid",
    };
  }
}

const oraclesInput = readJson(args.oracles, 16777216);
const oracles = oraclesInput.value;
check(oracles.schema === 1 && oracles.kind === "pi-b1-classic-reference-oracles", "unsupported B1 oracles");
check(oracles.qualification === "descriptive-b1-only", "B1 oracle qualification drift");
const oracle = oracles.fixtures?.[args.endpoint];
check(isObject(oracle), `unknown endpoint: ${args.endpoint}`);
check(Number.isSafeInteger(oracle.canonical?.bytes) && oracle.canonical.bytes > 0, "invalid canonical byte oracle");
check(typeof oracle.canonical?.sha256 === "string" && /^[0-9a-f]{64}$/.test(oracle.canonical.sha256), "invalid canonical hash oracle");
const limits = oracles.limits?.postflight;
const copyPolicy = oracles.limits?.copy;
const cappedCommandLimits = oracles.limits?.cappedCommand;
check(isObject(limits) && limits.maxSuffixBytes === 1048576, "postflight limits drift");
check(
  limits.hashChunkBytes === 65536 && limits.maxSmallJsonBytes === 16777216 && limits.maxCopyLauncherTargetBytes === 1024 && limits.maxCopyExecutableBytes === 16777216 && limits.maxOpenFiles === 1,
  "postflight hash/JSON/open-file limits drift",
);
check(
  isObject(cappedCommandLimits) &&
    cappedCommandLimits.maxArgumentCount === 64 &&
    cappedCommandLimits.maxArgumentBytes === 65536 &&
    cappedCommandLimits.maxArgumentBytesPerArgument === 4096,
  "capped-command argv limits drift",
);
check(exactJsonEqual(copyPolicy, {
  schema: 1,
  implementation: "gnu-coreutils-cp",
  executableBinding: "exact-launcher-symlink-and-resolved-file-identity",
  argv: ["cp", "--reflink=never", "fixture:<endpoint>", "namespace:session.jsonl"],
  destinationMode: "0600",
  opaqueImplementationInternalsClaimed: false,
  postflightVerification: "full-prefix-bytes-and-sha256",
}), "copy custody policy drift");

const resultRead = safeJson(args.result, limits.maxSmallJsonBytes);
const runRead = safeJson(args["run-result"], limits.maxSmallJsonBytes);
const result = resultRead.valid ? resultRead.value : null;
const run = runRead.valid ? runRead.value : null;
function inspectRunArgv(argv) {
  if (!Array.isArray(argv)) return { count: null, bytes: null, valid: false };
  let bytes = 0;
  let valid = argv.length > 0 && argv.length <= cappedCommandLimits.maxArgumentCount;
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (typeof value !== "string") return { count: argv.length, bytes: null, valid: false };
    const encodedBytes = Buffer.byteLength(value, "utf8") + 1;
    valid =
      valid &&
      !value.includes("\0") &&
      (index > 0 || value.length > 0) &&
      encodedBytes <= cappedCommandLimits.maxArgumentBytesPerArgument;
    bytes += encodedBytes;
  }
  return {
    count: argv.length,
    bytes,
    valid: valid && bytes <= cappedCommandLimits.maxArgumentBytes,
  };
}
const runArgv = inspectRunArgv(run?.argv);
const semanticValid =
  result?.schema === 1 &&
  result?.kind === "pi-b1-classic-core-diagnostic" &&
  result?.qualification === "descriptive-b1-only" &&
  result?.endpoint === args.endpoint &&
  result?.checks?.all === true &&
  allBooleansTrue(result.checks) &&
  result?.identities?.fixture?.expectedCanonicalBytes === oracle.canonical.bytes &&
  result?.identities?.fixture?.expectedCanonicalSha256 === oracle.canonical.sha256;
const runValid = run?.schema === 1 && run?.kind === "pi-b1-capped-command-result" && run?.qualification === "descriptive-b1-only";
const runnerIdentityValid =
  runValid &&
  run.tool?.sha256 === oracles.tools?.cappedCommand?.sha256 &&
  run.tool?.bytes === oracles.tools?.cappedCommand?.bytes;
const runSuccessful =
  runValid &&
  run.exitCode === 0 &&
  run.signal === null &&
  run.parentSignal === null &&
  run.spawnError === null &&
  run.ioError === null;
const runNoOverflow =
  runValid &&
  run.stdout?.overflow === false &&
  run.stderr?.overflow === false &&
  run.stdout?.published === true &&
  run.stderr?.published === true &&
  run.maxBytes === oracles.limits.cappedCommand.maxBytesPerStream;
const runArgvBound =
  runValid &&
  runArgv.valid &&
  run.argvCount === runArgv.count &&
  run.argvBytes === runArgv.bytes;
const runInvocationValid =
  runArgvBound &&
  run.argvSha256 === structuredSha256(run.argv) &&
  typeof run.environmentSha256 === "string" &&
  /^[0-9a-f]{64}$/.test(run.environmentSha256) &&
  Number.isSafeInteger(run.stdout?.bytes) &&
  run.stdout.bytes >= 0 &&
  run.stdout.bytes <= run.maxBytes &&
  Number.isSafeInteger(run.stderr?.bytes) &&
  run.stderr.bytes >= 0 &&
  run.stderr.bytes <= run.maxBytes &&
  /^[0-9a-f]{64}$/.test(run.stdout?.sha256 ?? "") &&
  /^[0-9a-f]{64}$/.test(run.stderr?.sha256 ?? "");
const runResultBound =
  runValid &&
  resultRead.valid &&
  run.stdout?.bytes === resultRead.bytes &&
  run.stdout?.sha256 === resultRead.sha256 &&
  resolve(run.stdout?.path ?? ".") === resultRead.path;
const runChildEnvironmentBound = semanticValid && runValid && run.environmentSha256 === result.process?.environmentSha256;

const copyLauncherPath = resolve(args["copy-executable"]);
check(args["copy-executable"] === copyLauncherPath, "copy launcher must be passed by absolute path");
check(basename(copyLauncherPath) === "cp" && basename(dirname(copyLauncherPath)) === "bin", "copy launcher is not bin/cp");
const copyStoreRoot = resolve(dirname(copyLauncherPath), "..");
check(copyStoreRoot.startsWith("/nix/store/") && dirname(copyStoreRoot) === "/nix/store", "copy launcher is not an exact Nix store output");
const copyLauncherInfo = lstatSync(copyLauncherPath);
check(copyLauncherInfo.isSymbolicLink(), "copy launcher must be the exact in-store cp symlink");
const copyLauncherTarget = readlinkSync(copyLauncherPath, "utf8");
const copyLauncherTargetBytes = Buffer.byteLength(copyLauncherTarget, "utf8");
check(copyLauncherTargetBytes > 0 && copyLauncherTargetBytes <= limits.maxCopyLauncherTargetBytes, "copy launcher target exceeds cap");
check(!copyLauncherTarget.includes("\0") && !copyLauncherTarget.includes("\n") && !copyLauncherTarget.includes("\r"), "copy launcher target contains control bytes");
const copyExecutablePath = realpathSync(copyLauncherPath);
check(copyExecutablePath.startsWith(`${copyStoreRoot}/`), "copy launcher resolves outside its store output");
const copyInfo = lstatSync(copyExecutablePath);
check(copyInfo.isFile() && !copyInfo.isSymbolicLink(), "resolved copy executable is not a regular file");
check((copyInfo.mode & 0o111) !== 0, "resolved copy executable lacks an execute bit");
const copyExecutableIdentity = hashFile(copyExecutablePath, limits.hashChunkBytes, limits.maxCopyExecutableBytes);

function inspectFixture() {
  const target = resolve(args.fixture);
  const before = lstatSync(target);
  check(before.isFile() && !before.isSymbolicLink(), "postflight fixture is not a regular file");
  const fd = openSync(target, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  const buffer = Buffer.allocUnsafe(limits.hashChunkBytes);
  const wholeHash = createHash("sha256");
  const prefixHash = createHash("sha256");
  const suffixParts = [];
  let bytes = 0;
  let suffixBytes = 0;
  let retainedSuffixBytes = 0;
  let suffixOverflow = false;
  let opened;
  let after;
  try {
    opened = fstatSync(fd);
    check(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino, "postflight fixture changed while opening");
    for (;;) {
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (count === 0) break;
      const chunk = buffer.subarray(0, count);
      wholeHash.update(chunk);
      const prefixCount = Math.max(0, Math.min(count, oracle.canonical.bytes - bytes));
      if (prefixCount > 0) prefixHash.update(chunk.subarray(0, prefixCount));
      if (prefixCount < count) {
        const suffix = chunk.subarray(prefixCount);
        suffixBytes += suffix.length;
        const keep = Math.max(0, Math.min(suffix.length, limits.maxSuffixBytes - retainedSuffixBytes));
        if (keep > 0) {
          suffixParts.push(Buffer.from(suffix.subarray(0, keep)));
          retainedSuffixBytes += keep;
        }
        if (suffixBytes > limits.maxSuffixBytes) suffixOverflow = true;
      }
      bytes += count;
    }
  } finally {
    try {
      after = fstatSync(fd);
    } finally {
      closeSync(fd);
    }
  }
  const unchanged =
    after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs && bytes === opened.size;
  const prefixSha256 = prefixHash.digest("hex");
  const prefixVerified = bytes >= oracle.canonical.bytes && prefixSha256 === oracle.canonical.sha256;
  let appendVerified = false;
  let appendedRecords = null;
  if (semanticValid && prefixVerified && !suffixOverflow) {
    try {
      const suffix = Buffer.concat(suffixParts, suffixBytes);
      if (suffix.length > 0 && suffix.at(-1) === 10) {
        const lines = suffix.subarray(0, -1).toString("utf8").split("\n");
        appendedRecords = lines.length;
        if (lines.length === 2 && lines.every(Boolean)) {
          const userEntry = JSON.parse(lines[0]);
          const assistantEntry = JSON.parse(lines[1]);
          appendVerified =
            isObject(userEntry) &&
            isObject(assistantEntry) &&
            userEntry.type === "message" &&
            assistantEntry.type === "message" &&
            userEntry.id === result.continuation.userEntryId &&
            assistantEntry.id === result.continuation.assistantEntryId &&
            userEntry.parentId === result.continuation.priorLeafId &&
            assistantEntry.parentId === userEntry.id &&
            structuredSha256(userEntry.message) === result.continuation.userMessageSha256 &&
            structuredSha256(assistantEntry.message) === result.continuation.assistantMessageSha256;
        }
      }
    } catch {
      appendVerified = false;
    }
  }
  return {
    path: target,
    present: true,
    valid: unchanged,
    mode: (opened.mode & 0o777).toString(8).padStart(4, "0"),
    bytes,
    sha256: wholeHash.digest("hex"),
    canonicalBytes: oracle.canonical.bytes,
    canonicalSha256: oracle.canonical.sha256,
    prefixSha256,
    prefixVerified,
    appendedBytes: bytes - oracle.canonical.bytes,
    appendedRecords,
    appendVerified,
    suffixBytes,
    suffixOverflow,
  };
}

const fixture = inspectFixture();
const selfIdentity = hashFile(process.argv[1], limits.hashChunkBytes, limits.maxSmallJsonBytes);
const toolAuthorityTools = Object.fromEntries(
  Object.entries(oracles.tools).map(([name, identity]) => [name, { bytes: identity.bytes, sha256: identity.sha256 }]),
);
const checks = {
  oracleEndpoint: true,
  postflightToolIdentity:
    selfIdentity.sha256 === oracles.tools?.postflight?.sha256 && selfIdentity.bytes === oracles.tools?.postflight?.bytes,
  copyExecutableBound: copyExecutableIdentity.bytes <= limits.maxCopyExecutableBytes,
  copyLauncherBound: copyLauncherTargetBytes <= limits.maxCopyLauncherTargetBytes,
  copyDestinationMode: fixture.mode === copyPolicy.destinationMode,
  resultPresent: resultRead.present,
  resultJson: resultRead.valid,
  semanticResult: Boolean(semanticValid),
  runResultPresent: runRead.present,
  runResultJson: runRead.valid,
  runnerIdentity: Boolean(runnerIdentityValid),
  runSuccessful: Boolean(runSuccessful),
  runNoOverflow: Boolean(runNoOverflow),
  runArgvBound: Boolean(runArgvBound),
  runInvocation: Boolean(runInvocationValid),
  runResultBound: Boolean(runResultBound),
  runChildEnvironmentBound: Boolean(runChildEnvironmentBound),
  fixtureStable: fixture.valid,
  originalPrefix: fixture.prefixVerified,
  suffixWithinCap: !fixture.suffixOverflow,
  exactContinuation: fixture.appendVerified,
};
const all = allBooleansTrue(checks);

writeJsonAtomic(args.output, {
  schema: 1,
  kind: "pi-b1-classic-postflight",
  qualification: "descriptive-b1-only",
  endpoint: args.endpoint,
  success: all,
  checks: { ...checks, all },
  oracles: { path: resolve(args.oracles), bytes: oraclesInput.bytes, sha256: oraclesInput.sha256 },
  toolAuthority: {
    sha256: structuredSha256(toolAuthorityTools),
    tools: toolAuthorityTools,
  },
  copyCustody: {
    policy: copyPolicy,
    launcher: {
      path: copyLauncherPath,
      type: "symlink",
      target: copyLauncherTarget,
      targetBytes: copyLauncherTargetBytes,
      resolvedPath: copyExecutablePath,
      storeOutput: { path: copyStoreRoot, name: basename(copyStoreRoot) },
    },
    executable: {
      path: copyExecutablePath,
      ...copyExecutableIdentity,
      storeOutput: { path: copyStoreRoot, name: basename(copyStoreRoot) },
    },
    normalizedArgv: copyPolicy.argv,
    destination: { path: fixture.path, mode: fixture.mode },
    verification: {
      kind: "full-prefix-bytes-and-sha256",
      canonicalBytes: oracle.canonical.bytes,
      canonicalSha256: oracle.canonical.sha256,
      verified: fixture.prefixVerified,
    },
  },
  fixture,
  result: {
    path: resultRead.path,
    present: resultRead.present,
    valid: resultRead.valid,
    bytes: resultRead.bytes,
    sha256: resultRead.sha256,
  },
  runResult: {
    path: runRead.path,
    present: runRead.present,
    valid: runRead.valid,
    bytes: runRead.bytes,
    sha256: runRead.sha256,
    exitCode: runValid ? run.exitCode : null,
    signal: runValid ? run.signal : null,
    parentSignal: runValid ? run.parentSignal : null,
    spawnError: runValid ? run.spawnError : null,
    ioError: runValid ? run.ioError : null,
    terminationReason: runValid ? run.terminationReason : null,
    maxBytes: runValid ? run.maxBytes : null,
    stdout: runValid ? run.stdout : null,
    stderr: runValid ? run.stderr : null,
    argv: runValid ? run.argv : null,
    argvSha256: runValid ? run.argvSha256 : null,
    argvCount: runArgv.count,
    argvBytes: runArgv.bytes,
    environmentSha256: runValid ? run.environmentSha256 : null,
    tool: runValid ? run.tool : null,
  },
  limits,
  tool: { path: resolve(process.argv[1]), ...selfIdentity },
});

if (!all) process.exitCode = 1;
