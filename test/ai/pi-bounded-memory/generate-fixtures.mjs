#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
  chmodSync,
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  writeSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import {
  bulkLine,
  check,
  exactJsonEqual,
  expectedTypeCounts,
  hashFile,
  increment,
  parseArgs,
  planAtomicOutputs,
  publishNoClobber,
  readJson,
  sha256,
  tailForScale,
  tempFileIdentity,
  unlinkOwnedTemp,
  validateSpec,
  writeJsonAtomic,
} from "./common.mjs";

const args = parseArgs(process.argv.slice(2), ["spec", "fixtures", "output"]);
const specInput = readJson(args.spec);
const spec = validateSpec(specInput.value);
const fixturesDir = resolve(args.fixtures);
if (!existsSync(fixturesDir)) mkdirSync(fixturesDir, { recursive: true, mode: 0o700 });
const fixturesInfo = lstatSync(fixturesDir);
check(fixturesInfo.isDirectory() && !fixturesInfo.isSymbolicLink(), "fixtures path is not a real directory");
const fixtureTargets = spec.scales.map((scale) => resolve(fixturesDir, scale.file));
for (let index = 0; index < fixtureTargets.length; index += 1) {
  check(dirname(fixtureTargets[index]) === fixturesDir, `fixture escapes output directory: ${spec.scales[index].file}`);
}
const outputPlan = planAtomicOutputs([...fixtureTargets, args.output]);
for (const { target, temp } of outputPlan) {
  check(!existsSync(target), `refusing to replace output: ${target}`);
  check(!existsSync(temp), `refusing to replace temporary output: ${temp}`);
}

const limits = spec.limits.generator;
const counters = {
  tempFilesCreated: 0,
  tempFilesRemovedOnFailure: 0,
  fsyncs: 0,
  closes: 0,
  boundedReopens: 0,
  noClobberPublishes: 0,
  canonicalPublished: 0,
  maxSimultaneousOpenFiles: 0,
};
const generated = [];

function writeAll(fd, bytes) {
  let offset = 0;
  while (offset < bytes.length) {
    const count = writeSync(fd, bytes, offset, bytes.length - offset);
    check(count > 0, "fixture write made no progress");
    offset += count;
  }
}

for (let scaleIndex = 0; scaleIndex < spec.scales.length; scaleIndex += 1) {
  const scale = spec.scales[scaleIndex];
  const { target, temp } = outputPlan[scaleIndex];
  let fd;
  let tempIdentity;
  let published = false;
  const rawHash = createHash("sha256");
  const bulkHash = createHash("sha256");
  const nestingHash = createHash("sha256");
  const typeCounts = {};
  let bytes = 0;
  let fileEntries = 0;
  let nonHeaderEntries = 0;
  let maxRecordBytes = 0;

  const emit = (entry, suppliedLine, isHeader = false, isBulk = false) => {
    const line = suppliedLine ?? Buffer.from(`${JSON.stringify(entry)}\n`, "utf8");
    check(line.length <= limits.maxRecordBytes, `record exceeds generator cap in ${scale.name}`);
    writeAll(fd, line);
    rawHash.update(line);
    if (fileEntries < 2 || isBulk) nestingHash.update(line);
    if (isBulk) bulkHash.update(line);
    bytes += line.length;
    fileEntries += 1;
    maxRecordBytes = Math.max(maxRecordBytes, line.length);
    if (!isHeader) {
      nonHeaderEntries += 1;
      increment(typeCounts, entry.type);
    }
  };

  try {
    fd = openSync(temp, "wx", 0o600);
    tempIdentity = tempFileIdentity(fd);
    counters.tempFilesCreated += 1;
    counters.maxSimultaneousOpenFiles = Math.max(counters.maxSimultaneousOpenFiles, 1);
    emit(spec.header, undefined, true);
    emit(spec.root);
    for (let index = 1; index <= scale.bulkEntries; index += 1) {
      const bulk = bulkLine(spec, index);
      emit(bulk.entry, bulk.line, false, true);
    }
    for (const entry of tailForScale(spec, scale.bulkEntries)) emit(entry);
    fsyncSync(fd);
    counters.fsyncs += 1;
    const openFd = fd;
    fd = undefined;
    closeSync(openFd);
    counters.closes += 1;

    const reopened = hashFile(temp, limits.hashChunkBytes);
    counters.boundedReopens += 1;
    counters.closes += 1;
    const rawSha256 = rawHash.digest("hex");
    check(reopened.bytes === bytes && reopened.sha256 === rawSha256, `reopen verification failed for ${scale.name}`);
    check(exactJsonEqual(typeCounts, expectedTypeCounts(spec, scale.bulkEntries)), `type counts drift for ${scale.name}`);
    check(fileEntries === nonHeaderEntries + 1, `header count drift for ${scale.name}`);
    chmodSync(temp, 0o444);
    publishNoClobber(temp, target, tempIdentity);
    published = true;
    counters.noClobberPublishes += 1;
    counters.canonicalPublished += 1;
    generated.push({
      scale: scale.name,
      file: scale.file,
      bulkEntries: scale.bulkEntries,
      bytes,
      sha256: rawSha256,
      fileEntries,
      nonHeaderEntries,
      typeCounts,
      bulkSha256: bulkHash.digest("hex"),
      nestingSha256: nestingHash.digest("hex"),
      limits: {
        maxRecordBytes,
        maxSimultaneousOpenFiles: 1,
        bulkEntryRecordsRetained: 1,
        chunksInFlight: 1,
      },
      cleanup: { descriptorClosed: true, tempAbsent: true, canonicalMode: "0444" },
    });
  } catch (error) {
    const cleanupErrors = [];
    if (fd !== undefined) {
      const openFd = fd;
      fd = undefined;
      try {
        closeSync(openFd);
        counters.closes += 1;
      } catch (cleanupError) {
        cleanupErrors.push(cleanupError);
      }
    }
    if (!published && tempIdentity !== undefined) {
      try {
        if (unlinkOwnedTemp(temp, tempIdentity)) counters.tempFilesRemovedOnFailure += 1;
      } catch (cleanupError) {
        cleanupErrors.push(cleanupError);
      }
    }
    if (cleanupErrors.length > 0) {
      throw new AggregateError([error, ...cleanupErrors], `fixture cleanup failed: ${target}`);
    }
    throw error;
  }
}

check(counters.maxSimultaneousOpenFiles <= limits.maxOpenFiles, "generator open-file limit exceeded");
const self = hashFile(process.argv[1], limits.hashChunkBytes);
const common = hashFile(new URL("./common.mjs", import.meta.url).pathname, limits.hashChunkBytes);
const runtimeExecutable = hashFile(process.execPath, limits.hashChunkBytes);
writeJsonAtomic(args.output, {
  schema: 1,
  kind: "pi-b1-fixture-generation",
  qualification: "descriptive-b1-only",
  spec: { sha256: specInput.sha256, bytes: specInput.bytes, seed: spec.seed },
  tools: {
    generator: { sha256: self.sha256, bytes: self.bytes },
    common: { sha256: common.sha256, bytes: common.bytes },
  },
  runtime: {
    executable: process.execPath,
    executableSha256: runtimeExecutable.sha256,
    version: process.version,
    platform: process.platform,
    arch: process.arch,
  },
  limits,
  counters,
  fixtures: generated,
});
