#!/usr/bin/env node
import { closeSync, constants, fstatSync, lstatSync, openSync, readSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  allBooleansTrue,
  check,
  deepFreeze,
  exactJsonEqual,
  hashFile,
  isObject,
  parseArgs,
  readJson,
  sha256,
  structuredSha256,
} from "./common.mjs";

const invokedAt = new Date().toISOString();
const invokedMonotonicNs = process.hrtime.bigint().toString();
const commandSha256 = structuredSha256({ execPath: process.execPath, execArgv: process.execArgv, argv: process.argv });
const environmentSha256 = structuredSha256(process.env);
const args = parseArgs(process.argv.slice(2), [
  "package-root",
  "fixture",
  "manifest",
  "oracles",
  "extension-manifest",
  "endpoint",
]);
check(typeof global.gc === "function", "run this diagnostic with --expose-gc");

const commandRoles = {
  "--package-root": "$PACKAGE_ROOT",
  "--fixture": "$FIXTURE",
  "--manifest": "$MANIFEST",
  "--oracles": "$ORACLES",
  "--extension-manifest": "$EXTENSION_MANIFEST",
  "--endpoint": "$ENDPOINT",
};
const normalizedArgv = [process.argv[0], resolve(process.argv[1])];
for (let index = 2; index < process.argv.length; index += 2) {
  const flag = process.argv[index];
  check(commandRoles[flag] !== undefined, `cannot normalize command option: ${flag}`);
  normalizedArgv.push(flag, commandRoles[flag]);
}
const normalizedCommand = { schema: 1, execArgv: process.execArgv, argv: normalizedArgv };
const fixturePath = resolve(args.fixture);
const fixtureStore = dirname(fixturePath);
const fixtureNamespace = dirname(fixtureStore);
check(fixtureNamespace !== resolve("/"), "fixture namespace must not be the filesystem root");
const environmentReplacements = [
  [resolve(args["package-root"]), "$PACKAGE_ROOT"],
  [fixturePath, "$FIXTURE"],
  [resolve(args.manifest), "$MANIFEST"],
  [resolve(args.oracles), "$ORACLES"],
  [resolve(args["extension-manifest"]), "$EXTENSION_MANIFEST"],
  [fixtureNamespace, "$FIXTURE_NAMESPACE"],
].sort((left, right) => right[0].length - left[0].length);
const normalizedEnvironmentIdentity = (() => {
  const value = {};
  for (const [key, rawValue] of Object.entries(process.env)) {
    let normalized = rawValue;
    for (const [literal, role] of environmentReplacements) normalized = normalized.split(literal).join(role);
    if (normalized === args.endpoint) normalized = "$ENDPOINT";
    value[key] = normalized;
  }
  return { sha256: structuredSha256(value), keyCount: Object.keys(value).length };
})();

const manifestInput = readJson(args.manifest);
const oraclesInput = readJson(args.oracles);
const extensionsInput = readJson(args["extension-manifest"]);
const manifest = manifestInput.value;
const oracles = oraclesInput.value;
const extensionManifest = extensionsInput.value;
check(manifest.schema === 1 && manifest.kind === "pi-b1-classic-fixture-manifest", "unsupported B1 manifest");
check(oracles.schema === 1 && oracles.kind === "pi-b1-classic-reference-oracles", "unsupported B1 oracles");
check(manifest.qualification === "descriptive-b1-only" && oracles.qualification === "descriptive-b1-only", "B1 qualification drift");
check(oracles.manifestObjectSha256 === structuredSha256(manifest), "manifest/oracle binding mismatch");
check(oracles.specSha256 === manifest.inputs?.spec?.sha256, "oracle/spec binding mismatch");
check(oracles.operationsSha256 === manifest.inputs?.operations?.sha256, "oracle/operations binding mismatch");
check(exactJsonEqual(oracles.tools, manifest.tools), "manifest/oracle tool binding mismatch");
check(exactJsonEqual(oracles.limits?.copy, manifest.limits?.copy), "manifest/oracle copy policy mismatch");
check(exactJsonEqual(oracles.limits?.postflight, manifest.limits?.postflight), "manifest/oracle postflight limits mismatch");
check(exactJsonEqual(oracles.limits?.seal, manifest.limits?.seal), "manifest/oracle seal limits mismatch");
check(exactJsonEqual(oracles.limits?.cappedCommand, manifest.limits?.cappedCommand), "manifest/oracle capped-command limits mismatch");
check(exactJsonEqual(extensionManifest, { extensions: [] }), "extension manifest must be exactly {extensions:[]}");
check(extensionsInput.sha256 === manifest.extensions?.sha256, "extension manifest identity mismatch");

const oracle = oracles.fixtures?.[args.endpoint];
const manifestFixture = manifest.fixtures?.find((entry) => entry.scale === args.endpoint);
check(isObject(oracle) && isObject(manifestFixture), `unknown endpoint: ${args.endpoint}`);
check(manifest.limits?.diagnosticPreflight?.maxHeaderBytes === 4096, "diagnostic header limit drift");
check(manifest.limits?.diagnosticPreflight?.maxPointEntriesRetained === 16, "diagnostic point limit drift");
check(exactJsonEqual(oracles.header, manifest.sessionHeader), "manifest/oracle header mismatch");
check(Array.isArray(oracles.invariantPointChecks) && Array.isArray(oracle.pointChecks), "oracle point sets missing");
const expectedPointChecks = [...oracles.invariantPointChecks, ...oracle.pointChecks];
check(expectedPointChecks.length <= 16, "oracle point set exceeds cap");
check(new Set(expectedPointChecks.map((point) => point.id)).size === expectedPointChecks.length, "duplicate oracle point ID");
check(exactJsonEqual(oracle.canonical, manifestFixture.canonical), "fixture manifest/oracle mismatch");
check(exactJsonEqual(oracle.before.typeCounts, manifestFixture.typeCounts), "type manifest/oracle mismatch");

const commonPath = new URL("./common.mjs", import.meta.url).pathname;
const selfIdentity = hashFile(process.argv[1], 65536);
const commonIdentity = hashFile(commonPath, 65536);
check(selfIdentity.sha256 === manifest.tools?.diagnostic?.sha256, "diagnostic tool identity mismatch");
check(commonIdentity.sha256 === manifest.tools?.common?.sha256, "common tool identity mismatch");
const runtimeExecutable = hashFile(process.execPath, 65536);
check(process.version === manifest.runtime?.version, "runtime version mismatch");
check(process.platform === manifest.runtime?.platform && process.arch === manifest.runtime?.arch, "runtime platform mismatch");
check(runtimeExecutable.sha256 === manifest.runtime?.executableSha256, "runtime executable mismatch");
check(manifest.package?.buildRuntime?.version === process.version, "package build runtime version mismatch");
check(manifest.package?.buildRuntime?.executableSha256 === runtimeExecutable.sha256, "package build runtime executable mismatch");

const packageRoot = realpathSync(args["package-root"]);
const modulePath = resolve(packageRoot, "lib/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js");
const sourceMapPath = `${modulePath}.map`;
const packageJsonPath = resolve(packageRoot, "lib/node_modules/@earendil-works/pi-coding-agent/package.json");
check(realpathSync(modulePath) === modulePath, "session-manager module must be a real canonical file");
const moduleIdentity = hashFile(modulePath, 65536);
const sourceMapIdentity = hashFile(sourceMapPath, 65536);
const packageJsonIdentity = hashFile(packageJsonPath, 65536);
check(moduleIdentity.sha256 === manifest.package?.hashes?.sessionManagerRuntime, "session-manager runtime hash mismatch");
check(sourceMapIdentity.sha256 === manifest.package?.hashes?.sessionManagerSourceMap, "session-manager source-map hash mismatch");
check(packageJsonIdentity.sha256 === manifest.package?.hashes?.codingAgentPackage, "coding-agent package hash mismatch");

function checkFixtureForOpen() {
  const limits = manifest.limits.diagnosticPreflight;
  const path = resolve(args.fixture);
  const info = lstatSync(path);
  check(info.isFile() && !info.isSymbolicLink(), "fixture is not a regular file");
  check(info.size === oracle.canonical.bytes, "fixture size differs from immutable oracle");
  const buffer = Buffer.allocUnsafe(limits.maxHeaderBytes);
  const fd = openSync(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  let length = 0;
  let newline = -1;
  try {
    const opened = fstatSync(fd);
    check(opened.isFile() && opened.dev === info.dev && opened.ino === info.ino && opened.size === info.size, "fixture changed while opening");
    while (length < buffer.length && newline < 0) {
      const count = readSync(fd, buffer, length, buffer.length - length, null);
      if (count === 0) break;
      length += count;
      newline = buffer.subarray(0, length).indexOf(10);
    }
    const after = fstatSync(fd);
    check(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs, "fixture changed during bounded header read");
  } finally {
    closeSync(fd);
  }
  check(newline >= 0, "fixture header exceeds bounded header check");
  const rawHeader = Buffer.from(buffer.subarray(0, newline + 1));
  check(rawHeader.length === oracles.header.bytes, "fixture header byte count drift");
  check(sha256(rawHeader) === oracles.header.sha256, "fixture header hash drift");
  let header;
  try {
    header = JSON.parse(rawHeader.subarray(0, -1).toString("utf8"));
  } catch (error) {
    throw new Error(`invalid bounded fixture header: ${error.message}`);
  }
  check(exactJsonEqual(header, oracles.header.object), "fixture header object drift");
  return {
    observedBytes: info.size,
    expectedCanonicalBytes: oracle.canonical.bytes,
    expectedCanonicalSha256: oracle.canonical.sha256,
    headerBytes: rawHeader.length,
    headerSha256: oracles.header.sha256,
    bytesRead: length,
    maxHeaderBytes: limits.maxHeaderBytes,
    fullIdentityVerification: "deferred-to-external-postflight-prefix-sha256",
  };
}

const fixtureOpenCheck = checkFixtureForOpen();

async function gcTurns() {
  for (let turn = 0; turn < 3; turn += 1) {
    global.gc();
    await new Promise((resolveTurn) => setImmediate(resolveTurn));
  }
}

function rawUsage() {
  const memoryUsage = process.memoryUsage();
  const resourceUsage = process.resourceUsage();
  const maxRSSBytes = ["darwin", "linux"].includes(process.platform) ? resourceUsage.maxRSS * 1024 : null;
  check(Number.isSafeInteger(memoryUsage.rss) && Number.isSafeInteger(maxRSSBytes), "unsupported RSS units");
  return {
    memoryUsage,
    resourceUsage,
    rssBytes: memoryUsage.rss,
    maxRSSBytes,
    units: {
      memoryUsage: "bytes",
      rssBytes: "bytes",
      resourceUsageMaxRSS: "KiB-raw",
      maxRSSBytes: "bytes",
      cpuTimes: "microseconds-raw",
    },
    sampledAt: new Date().toISOString(),
    monotonicNs: process.hrtime.bigint().toString(),
  };
}

const imported = await import(pathToFileURL(modulePath).href);
check(typeof imported.SessionManager?.open === "function", "classic module lacks SessionManager.open");
await gcTurns();
const preOpenUsage = rawUsage();

const manager = imported.SessionManager.open(args.fixture);
check(Array.isArray(manager.fileEntries), "classic fileEntries field is unavailable");
check(manager.byId instanceof Map, "classic byId field is unavailable");
const beforeCounts = { fileEntries: manager.fileEntries.length, byId: manager.byId.size };
check(beforeCounts.fileEntries === oracle.before.fileEntries && beforeCounts.byId === oracle.before.byId, "classic retained counts before continuation drift");
check(manager.getLeafId() === oracle.before.activeLeaf.id, "classic active leaf before continuation drift");

for (const expected of expectedPointChecks) {
  const entry = manager.getEntry(expected.id);
  check(entry !== undefined && structuredSha256(entry) === expected.sha256, `classic point read drift: ${expected.id}`);
}
const branchPoint = manager.getEntry(oracle.branch.pointId);
const leftChild = manager.getEntry(oracle.branch.children[0]);
const rightChild = manager.getEntry(oracle.branch.children[1]);
const leftLeaf = manager.getEntry(oracle.branch.leftLeafId);
const rightLeaf = manager.getEntry(oracle.branch.rightLeafId);
check(branchPoint && leftChild && rightChild && leftLeaf && rightLeaf, "classic branch point read missing");
check(leftChild.parentId === branchPoint.id && rightChild.parentId === branchPoint.id, "classic two-way branch drift");
check(leftLeaf.parentId === leftChild.id && rightLeaf.parentId === rightChild.id, "classic branch leaf drift");
check(manager.getLabel(oracle.label.targetId) === oracle.label.value, "classic label drift");
const snapshotEntry = manager.getEntry(oracle.snapshot.entryId);
check(snapshotEntry && structuredSha256(snapshotEntry) === oracle.snapshot.entrySha256, "classic snapshot entry drift");
check(structuredSha256(snapshotEntry.data) === oracle.snapshot.dataSha256, "classic snapshot data drift");

const beforeContext = deepFreeze(manager.buildSessionContext());
const beforeContextSha256 = structuredSha256(beforeContext);
check(beforeContextSha256 === oracle.before.activeContextSha256, "classic before context digest drift");
check(exactJsonEqual(beforeContext, oracle.before.activeContext), "classic before context object drift");
check(exactJsonEqual(beforeContext.model, oracle.before.model) && beforeContext.thinkingLevel === oracle.before.thinkingLevel, "classic before settings drift");
const postOpenContextUsage = rawUsage();

const continuationUser = JSON.parse(JSON.stringify(oracles.continuation.userMessage));
const continuationAssistant = JSON.parse(JSON.stringify(oracles.continuation.assistantMessage));
check(structuredSha256(continuationUser) === oracles.continuation.userMessageSha256, "continuation user identity drift");
check(structuredSha256(continuationAssistant) === oracles.continuation.assistantMessageSha256, "continuation assistant identity drift");
const appendedUserId = manager.appendMessage(continuationUser);
const appendedAssistantId = manager.appendMessage(continuationAssistant);
check(typeof appendedUserId === "string" && typeof appendedAssistantId === "string" && appendedUserId !== appendedAssistantId, "invalid appended IDs");
const appendedUser = manager.getEntry(appendedUserId);
const appendedAssistant = manager.getEntry(appendedAssistantId);
check(appendedUser?.parentId === oracle.before.activeLeaf.id, "continuation user parent drift");
check(appendedAssistant?.parentId === appendedUserId, "continuation assistant parent drift");
check(structuredSha256(appendedUser.message) === oracles.continuation.userMessageSha256, "appended user message drift");
check(structuredSha256(appendedAssistant.message) === oracles.continuation.assistantMessageSha256, "appended assistant message drift");

const afterCounts = { fileEntries: manager.fileEntries.length, byId: manager.byId.size };
check(afterCounts.fileEntries === oracle.after.fileEntries && afterCounts.byId === oracle.after.byId, "classic retained counts after continuation drift");
check(manager.getLeafId() === appendedAssistantId, "classic active leaf after continuation drift");
const afterContext = deepFreeze(manager.buildSessionContext());
const afterContextSha256 = structuredSha256(afterContext);
check(afterContextSha256 === oracle.after.activeContextSha256, "classic after context digest drift");
check(exactJsonEqual(afterContext, oracle.after.activeContext), "classic after context object drift");
check(exactJsonEqual(afterContext.model, oracle.after.model) && afterContext.thinkingLevel === oracle.after.thinkingLevel, "classic after settings drift");

await gcTurns();
const retainedReadyUsage = rawUsage();
check(manager.fileEntries.length === afterCounts.fileEntries && manager.byId.size === afterCounts.byId, "retained counts changed at barrier");
check(manager.getLeafId() === appendedAssistantId, "active leaf changed at retained barrier");

const checks = {
  identities: {
    manifestOracle: true,
    runtime: true,
    package: true,
    tools: true,
    extensionManifest: true,
  },
  fixture: {
    regularFile: true,
    size: true,
    boundedHeader: true,
    immutableOracleTrusted: true,
    fullHashDeferredToPostflight: true,
  },
  semantic: {
    contextBefore: true,
    contextAfter: true,
    modelBefore: true,
    modelAfter: true,
    thinkingBefore: true,
    thinkingAfter: true,
    label: true,
    snapshot: true,
    branch: true,
    fixedPointReads: true,
    continuation: true,
    activeLeafBefore: true,
    activeLeafAfter: true,
  },
  counts: { before: true, after: true, retainedBarrier: true },
};
check(allBooleansTrue(checks), "internal diagnostic check aggregation failure");

const result = {
  schema: 1,
  kind: "pi-b1-classic-core-diagnostic",
  qualification: "descriptive-b1-only",
  endpoint: args.endpoint,
  checks: { ...checks, all: true },
  process: {
    pid: process.pid,
    ppid: process.ppid,
    invokedAt,
    invokedMonotonicNs,
    completedAt: new Date().toISOString(),
    completedMonotonicNs: process.hrtime.bigint().toString(),
    commandSha256,
    environmentSha256,
    environmentKeyCount: Object.keys(process.env).length,
    normalizedCommand: {
      policy: "replace-cli-values-with-stable-roles-v1",
      value: normalizedCommand,
      sha256: structuredSha256(normalizedCommand),
    },
    normalizedEnvironment: {
      policy: "replace-cli-path-and-fixture-namespace-occurrences-and-exact-endpoint-with-stable-roles-v1",
      sha256: normalizedEnvironmentIdentity.sha256,
      keyCount: normalizedEnvironmentIdentity.keyCount,
    },
  },
  identities: {
    manifest: { path: resolve(args.manifest), bytes: manifestInput.bytes, sha256: manifestInput.sha256 },
    oracles: { path: resolve(args.oracles), bytes: oraclesInput.bytes, sha256: oraclesInput.sha256 },
    fixture: {
      path: resolve(args.fixture),
      observedBytes: fixtureOpenCheck.observedBytes,
      expectedCanonicalBytes: fixtureOpenCheck.expectedCanonicalBytes,
      expectedCanonicalSha256: fixtureOpenCheck.expectedCanonicalSha256,
      headerBytes: fixtureOpenCheck.headerBytes,
      headerSha256: fixtureOpenCheck.headerSha256,
      fullIdentityVerifiedInChild: false,
    },
    extensionManifest: { path: resolve(args["extension-manifest"]), bytes: extensionsInput.bytes, sha256: extensionsInput.sha256 },
    package: {
      root: packageRoot,
      source: manifest.package.source,
      crosswalkHashes: manifest.package.hashes,
      buildRuntime: manifest.package.buildRuntime,
      sourceMap: manifest.package.sourceMap,
      causalLocations: manifest.package.causalLocations,
      sessionManager: { path: modulePath, ...moduleIdentity },
      sessionManagerSourceMap: { path: sourceMapPath, ...sourceMapIdentity },
      codingAgentPackage: { path: packageJsonPath, ...packageJsonIdentity },
    },
    runtime: {
      executable: process.execPath,
      executableSha256: runtimeExecutable.sha256,
      version: process.version,
      platform: process.platform,
      arch: process.arch,
    },
    tools: {
      diagnostic: { path: resolve(process.argv[1]), ...selfIdentity },
      common: { path: resolve(commonPath), ...commonIdentity },
    },
  },
  fixtureOpenCheck,
  limits: { cappedCommand: manifest.limits.cappedCommand, diagnosticPreflight: manifest.limits.diagnosticPreflight },
  semantic: {
    beforeContextSha256,
    afterContextSha256,
    modelBefore: beforeContext.model,
    modelAfter: afterContext.model,
    thinkingBefore: beforeContext.thinkingLevel,
    thinkingAfter: afterContext.thinkingLevel,
    label: oracle.label,
    snapshot: oracle.snapshot,
    branch: oracle.branch,
    pointReads: { count: expectedPointChecks.length, matched: true },
  },
  continuation: {
    userEntryId: appendedUserId,
    assistantEntryId: appendedAssistantId,
    priorLeafId: oracle.before.activeLeaf.id,
    userMessageSha256: oracles.continuation.userMessageSha256,
    assistantMessageSha256: oracles.continuation.assistantMessageSha256,
  },
  retained: { before: beforeCounts, after: afterCounts, barrier: { ...afterCounts, activeLeafId: appendedAssistantId } },
  usage: { preOpen: preOpenUsage, postOpenContext: postOpenContextUsage, retainedReadySamples: [retainedReadyUsage] },
};
process.stdout.write(`${JSON.stringify(result)}\n`);
