#!/usr/bin/env node
import { resolve } from "node:path";
import {
  allBooleansTrue,
  exactJsonEqual,
  hashFile,
  isObject,
  parseArgs,
  readJson,
  structuredSha256,
  writeJsonAtomic,
} from "./common.mjs";

const args = parseArgs(process.argv.slice(2), ["low", "low-postflight", "high", "high-postflight", "output"]);
const SMALL_JSON_BYTES = 16777216;
const SHA256 = /^[0-9a-f]{64}$/;

function safeJson(path) {
  const target = resolve(path);
  try {
    const input = readJson(target, SMALL_JSON_BYTES);
    return { path: target, present: true, valid: true, bytes: input.bytes, sha256: input.sha256, value: input.value };
  } catch (error) {
    const absent = error?.code === "ENOENT";
    return {
      path: target,
      present: !absent,
      valid: false,
      bytes: error?.identity?.bytes ?? null,
      sha256: error?.identity?.sha256 ?? null,
    };
  }
}

function exactKeys(value, keys) {
  return isObject(value) && exactJsonEqual(Object.keys(value).sort(), [...keys].sort());
}

function nonnegativeSafeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function compactIdentity(value) {
  return isObject(value) && nonnegativeSafeInteger(value.bytes) && SHA256.test(value.sha256)
    ? { bytes: value.bytes, sha256: value.sha256 }
    : null;
}

const memoryKeys = ["rss", "heapTotal", "heapUsed", "external", "arrayBuffers"];
const resourceKeys = [
  "userCPUTime",
  "systemCPUTime",
  "maxRSS",
  "sharedMemorySize",
  "unsharedDataSize",
  "unsharedStackSize",
  "minorPageFault",
  "majorPageFault",
  "swappedOut",
  "fsRead",
  "fsWrite",
  "ipcSent",
  "ipcReceived",
  "signalsCount",
  "voluntaryContextSwitches",
  "involuntaryContextSwitches",
];
const expectedUnits = {
  memoryUsage: "bytes",
  rssBytes: "bytes",
  resourceUsageMaxRSS: "KiB-raw",
  maxRSSBytes: "bytes",
  cpuTimes: "microseconds-raw",
};

function validateUsage(sample) {
  if (!isObject(sample)) return false;
  if (!exactKeys(sample.memoryUsage, memoryKeys) || !exactKeys(sample.resourceUsage, resourceKeys)) return false;
  if (!Object.values(sample.memoryUsage).every(nonnegativeSafeInteger)) return false;
  if (!Object.values(sample.resourceUsage).every(nonnegativeSafeInteger)) return false;
  if (!exactJsonEqual(sample.units, expectedUnits)) return false;
  if (!nonnegativeSafeInteger(sample.rssBytes) || sample.rssBytes !== sample.memoryUsage.rss) return false;
  if (!nonnegativeSafeInteger(sample.maxRSSBytes)) return false;
  if (!Number.isSafeInteger(sample.resourceUsage.maxRSS * 1024) || sample.maxRSSBytes !== sample.resourceUsage.maxRSS * 1024) return false;
  if (typeof sample.sampledAt !== "string" || !Number.isFinite(Date.parse(sample.sampledAt))) return false;
  return typeof sample.monotonicNs === "string" && /^[0-9]+$/.test(sample.monotonicNs);
}

const summarySelf = hashFile(process.argv[1], 65536, SMALL_JSON_BYTES);

function endpoint(role, expectedEndpoint, resultPath, postflightPath) {
  const resultRead = safeJson(resultPath);
  const postRead = safeJson(postflightPath);
  const result = resultRead.valid ? resultRead.value : null;
  const postflight = postRead.valid ? postRead.value : null;
  const semanticValid =
    result?.schema === 1 &&
    result?.kind === "pi-b1-classic-core-diagnostic" &&
    result?.qualification === "descriptive-b1-only" &&
    result?.endpoint === expectedEndpoint &&
    result?.checks?.all === true &&
    allBooleansTrue(result.checks);
  const postflightValid =
    postflight?.schema === 1 &&
    postflight?.kind === "pi-b1-classic-postflight" &&
    postflight?.qualification === "descriptive-b1-only" &&
    postflight?.endpoint === expectedEndpoint;
  const resultBound =
    postflightValid &&
    resultRead.present &&
    postflight.result?.bytes === resultRead.bytes &&
    postflight.result?.sha256 === resultRead.sha256;
  const runResultValid =
    postflightValid &&
    postflight.runResult?.present === true &&
    postflight.runResult?.valid === true &&
    postflight.runResult?.exitCode === 0 &&
    postflight.runResult?.signal === null &&
    postflight.runResult?.parentSignal === null &&
    postflight.runResult?.spawnError === null &&
    postflight.runResult?.ioError === null &&
    postflight.runResult?.stdout?.overflow === false &&
    postflight.runResult?.stderr?.overflow === false &&
    postflight.runResult?.stdout?.published === true &&
    postflight.runResult?.stderr?.published === true;
  const postflightSuccess =
    postflightValid &&
    postflight.success === true &&
    postflight.checks?.all === true &&
    allBooleansTrue(postflight.checks);

  const retainedSamples = semanticValid ? result.usage?.retainedReadySamples : null;
  const exactlyOneRetainedReadySample = Array.isArray(retainedSamples) && retainedSamples.length === 1;
  const retainedReadySample = exactlyOneRetainedReadySample ? retainedSamples[0] : null;
  const rawUsageValid = exactlyOneRetainedReadySample && validateUsage(retainedReadySample);
  const retained = semanticValid ? result.retained : null;
  const retainedCountsValid =
    isObject(retained?.before) &&
    isObject(retained?.after) &&
    isObject(retained?.barrier) &&
    exactKeys(retained.before, ["fileEntries", "byId"]) &&
    exactKeys(retained.after, ["fileEntries", "byId"]) &&
    exactKeys(retained.barrier, ["fileEntries", "byId", "activeLeafId"]) &&
    nonnegativeSafeInteger(retained.before.fileEntries) &&
    nonnegativeSafeInteger(retained.before.byId) &&
    nonnegativeSafeInteger(retained.after.fileEntries) &&
    nonnegativeSafeInteger(retained.after.byId) &&
    retained.after.fileEntries === retained.before.fileEntries + 2 &&
    retained.after.byId === retained.before.byId + 2 &&
    retained.barrier.fileEntries === retained.after.fileEntries &&
    retained.barrier.byId === retained.after.byId &&
    typeof result?.continuation?.assistantEntryId === "string" &&
    result.continuation.assistantEntryId.length > 0 &&
    retained.barrier.activeLeafId === result?.continuation?.assistantEntryId;

  const toolAuthorityValid =
    postflightValid &&
    isObject(postflight.toolAuthority?.tools) &&
    exactJsonEqual(
      Object.keys(postflight.toolAuthority.tools).sort(),
      ["common", "generator", "reference", "diagnostic", "cappedCommand", "postflight", "summary", "seal"].sort(),
    ) &&
    postflight.toolAuthority.sha256 === structuredSha256(postflight.toolAuthority.tools) &&
    exactJsonEqual(compactIdentity(postflight.toolAuthority.tools.summary), summarySelf) &&
    exactJsonEqual(compactIdentity(postflight.tool), compactIdentity(postflight.toolAuthority.tools.postflight)) &&
    exactJsonEqual(compactIdentity(postflight.runResult?.tool), compactIdentity(postflight.toolAuthority.tools.cappedCommand)) &&
    exactJsonEqual(compactIdentity(result?.identities?.tools?.diagnostic), compactIdentity(postflight.toolAuthority.tools.diagnostic)) &&
    exactJsonEqual(compactIdentity(result?.identities?.tools?.common), compactIdentity(postflight.toolAuthority.tools.common));
  const normalizedInvocationValid =
    semanticValid &&
    SHA256.test(result.process?.commandSha256) &&
    SHA256.test(result.process?.environmentSha256) &&
    isObject(result.process?.normalizedCommand?.value) &&
    result.process?.normalizedCommand?.sha256 === structuredSha256(result.process?.normalizedCommand?.value) &&
    result.process?.normalizedCommand?.policy === "replace-cli-values-with-stable-roles-v1" &&
    SHA256.test(result.process?.normalizedEnvironment?.sha256) &&
    result.process?.normalizedEnvironment?.policy === "replace-cli-path-and-fixture-namespace-occurrences-and-exact-endpoint-with-stable-roles-v1" &&
    result.process?.normalizedEnvironment?.keyCount === result.process?.environmentKeyCount;
  const processIdentityValid =
    semanticValid &&
    Number.isSafeInteger(result.process?.pid) &&
    result.process.pid > 0 &&
    Number.isSafeInteger(result.process?.ppid) &&
    result.process.ppid >= 0 &&
    Number.isFinite(Date.parse(result.process?.invokedAt)) &&
    Number.isFinite(Date.parse(result.process?.completedAt)) &&
    typeof result.process?.invokedMonotonicNs === "string" &&
    /^[0-9]+$/.test(result.process.invokedMonotonicNs) &&
    typeof result.process?.completedMonotonicNs === "string" &&
    /^[0-9]+$/.test(result.process.completedMonotonicNs);
  const oracleBindingValid =
    semanticValid &&
    postflightValid &&
    exactJsonEqual(compactIdentity(result.identities?.oracles), compactIdentity(postflight.oracles));

  let commonIdentity = null;
  if (semanticValid && postflightValid) {
    commonIdentity = {
      manifest: compactIdentity(result.identities?.manifest),
      oracles: compactIdentity(result.identities?.oracles),
      sourcePackage: result.identities?.package ?? null,
      runtime: result.identities?.runtime ?? null,
      extensionManifest: compactIdentity(result.identities?.extensionManifest),
      tools: {
        authority: postflight.toolAuthority,
        diagnostic: compactIdentity(result.identities?.tools?.diagnostic),
        common: compactIdentity(result.identities?.tools?.common),
        runner: compactIdentity(postflight.runResult?.tool),
        postflight: compactIdentity(postflight.tool),
        copyLauncher: postflight.copyCustody?.launcher ?? null,
        copyExecutable: {
          ...compactIdentity(postflight.copyCustody?.executable),
          path: postflight.copyCustody?.executable?.path ?? null,
          storeOutput: postflight.copyCustody?.executable?.storeOutput ?? null,
        },
      },
      copyPolicy: postflight.copyCustody?.policy ?? null,
      normalizedInvocation: {
        command: result.process?.normalizedCommand ?? null,
        environment: result.process?.normalizedEnvironment ?? null,
      },
    };
  }
  const commonIdentityValid =
    commonIdentity !== null &&
    Object.values({
      manifest: commonIdentity.manifest,
      oracles: commonIdentity.oracles,
      extensionManifest: commonIdentity.extensionManifest,
      diagnostic: commonIdentity.tools.diagnostic,
      common: commonIdentity.tools.common,
      runner: commonIdentity.tools.runner,
      postflight: commonIdentity.tools.postflight,
    }).every((identity) => identity !== null) &&
    isObject(commonIdentity.sourcePackage) &&
    isObject(commonIdentity.runtime) &&
    commonIdentity.tools.copyExecutable.bytes !== undefined &&
    isObject(commonIdentity.tools.copyLauncher) &&
    toolAuthorityValid &&
    normalizedInvocationValid &&
    oracleBindingValid;

  const checks = {
    resultPresent: resultRead.present,
    resultJson: resultRead.valid,
    semanticResult: Boolean(semanticValid),
    postflightPresent: postRead.present,
    postflightJson: postRead.valid,
    postflightSuccess: Boolean(postflightSuccess),
    runResultValid: Boolean(runResultValid),
    resultBound: Boolean(resultBound),
    exactlyOneRetainedReadySample: Boolean(exactlyOneRetainedReadySample),
    rawUsageSchemaAndUnits: Boolean(rawUsageValid),
    retainedBarrier: Boolean(retainedCountsValid),
    toolAuthority: Boolean(toolAuthorityValid),
    normalizedInvocation: Boolean(normalizedInvocationValid),
    processIdentity: Boolean(processIdentityValid),
    oracleBinding: Boolean(oracleBindingValid),
    commonIdentityCandidate: Boolean(commonIdentityValid),
  };
  const localSuccess = allBooleansTrue(checks);
  return {
    role,
    expectedEndpoint,
    success: false,
    localSuccess,
    checks,
    result: {
      path: resultRead.path,
      present: resultRead.present,
      valid: resultRead.valid,
      bytes: resultRead.bytes,
      sha256: resultRead.sha256,
    },
    postflight: {
      path: postRead.path,
      present: postRead.present,
      valid: postRead.valid,
      bytes: postRead.bytes,
      sha256: postRead.sha256,
      runResult: postflightValid ? postflight.runResult : null,
      fixture: postflightValid ? postflight.fixture : null,
      copyCustody: postflightValid ? postflight.copyCustody : null,
      oracles: postflightValid ? postflight.oracles : null,
    },
    invocationRaw: normalizedInvocationValid
      ? {
          commandSha256: result.process.commandSha256,
          environmentSha256: result.process.environmentSha256,
          environmentKeyCount: result.process.environmentKeyCount,
        }
      : null,
    retainedReadySample: rawUsageValid ? retainedReadySample : null,
    rawRSSBytes: rawUsageValid ? retainedReadySample.rssBytes : null,
    maxRSSBytes: rawUsageValid ? retainedReadySample.maxRSSBytes : null,
    retainedCounts: retainedCountsValid ? retained : null,
    commonIdentity: commonIdentityValid ? commonIdentity : null,
  };
}

const low = endpoint("low", "16m", args.low, args["low-postflight"]);
const high = endpoint("high", "1g", args.high, args["high-postflight"]);
const commonIdentityEqual =
  low.commonIdentity !== null && high.commonIdentity !== null && exactJsonEqual(low.commonIdentity, high.commonIdentity);
low.checks.commonIdentityEqual = commonIdentityEqual;
high.checks.commonIdentityEqual = commonIdentityEqual;
low.success = low.localSuccess && commonIdentityEqual;
high.success = high.localSuccess && commonIdentityEqual;
low.checks.all = low.success;
high.checks.all = high.success;
const complete = low.success && high.success;

const delta = (highValue, lowValue) =>
  Number.isSafeInteger(highValue) && Number.isSafeInteger(lowValue) ? highValue - lowValue : null;
const summary = {
  schema: 1,
  kind: "pi-b1-classic-diagnostic-summary",
  qualification: "descriptive-b1-only",
  disposition: complete ? "diagnostic-complete" : "diagnostic-incomplete",
  success: complete,
  paired32MiBVerdict: "not-applicable-b1-descriptive",
  thresholdBytes: null,
  commonIdentity: {
    equal: commonIdentityEqual,
    lowSha256: low.commonIdentity === null ? null : structuredSha256(low.commonIdentity),
    highSha256: high.commonIdentity === null ? null : structuredSha256(high.commonIdentity),
    value: commonIdentityEqual ? low.commonIdentity : null,
  },
  endpoints: { low, high },
  deltasHighMinusLow: {
    rawRSSBytes: delta(high.rawRSSBytes, low.rawRSSBytes),
    maxRSSBytes: delta(high.maxRSSBytes, low.maxRSSBytes),
    beforeFileEntries: delta(high.retainedCounts?.before?.fileEntries, low.retainedCounts?.before?.fileEntries),
    beforeById: delta(high.retainedCounts?.before?.byId, low.retainedCounts?.before?.byId),
    afterFileEntries: delta(high.retainedCounts?.after?.fileEntries, low.retainedCounts?.after?.fileEntries),
    afterById: delta(high.retainedCounts?.after?.byId, low.retainedCounts?.after?.byId),
  },
  tool: { path: resolve(process.argv[1]), ...summarySelf },
};
writeJsonAtomic(args.output, summary);
if (!complete) process.exitCode = 1;
