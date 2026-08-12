#!/usr/bin/env node
import { createHash } from "node:crypto";
import { lstatSync, realpathSync } from "node:fs";
import { resolve } from "node:path";
import {
  activeContextFromSpec,
  bulkLine,
  check,
  compareUtf8,
  edgeOf,
  exactJsonEqual,
  expectedTypeCounts,
  hashFile,
  increment,
  isObject,
  parseArgs,
  readJson,
  sha256,
  stableStringify,
  streamJsonLines,
  structuredSha256,
  tailForScale,
  updateStructuredFold,
  validateSpec,
  writeJsonAtomic,
} from "./common.mjs";

const args = parseArgs(process.argv.slice(2), [
  "spec",
  "fixtures",
  "generation",
  "operations",
  "generator",
  "reference",
  "diagnostic",
  "source-identity",
  "crosswalk",
  "empty-extensions",
  "manifest",
  "oracles",
]);
check(realpathSync(args.reference) === realpathSync(process.argv[1]), "--reference does not name this program");

const specInput = readJson(args.spec);
const spec = validateSpec(specInput.value);
const smallLimit = spec.limits.smallJsonBytes;
const generationInput = readJson(args.generation, smallLimit);
const operationsInput = readJson(args.operations, smallLimit);
const sourceInput = readJson(args["source-identity"], smallLimit);
const crosswalkInput = readJson(args.crosswalk, smallLimit);
const extensionsInput = readJson(args["empty-extensions"], smallLimit);
const generation = generationInput.value;
const operations = operationsInput.value;
const sourceIdentity = sourceInput.value;
const crosswalk = crosswalkInput.value;
const extensionManifest = extensionsInput.value;

check(generation.schema === 1 && generation.kind === "pi-b1-fixture-generation", "unsupported generation record");
check(generation.qualification === "descriptive-b1-only", "generation qualification drift");
check(generation.spec?.sha256 === specInput.sha256 && generation.spec?.bytes === specInput.bytes, "generation/spec identity mismatch");
check(Array.isArray(generation.fixtures) && generation.fixtures.length === spec.scales.length, "generation fixture table drift");
check(exactJsonEqual(generation.limits, spec.limits.generator), "generation limit table drift");
const expectedOperations = {
  schema: 1,
  kind: "pi-b1-operation-oracle-table",
  qualification: "descriptive-b1-only",
  rows: [
    {
      operation: "classic-open",
      projection: "direct fileEntries.length and byId.size",
      itemProjection: "fileEntries-length with byId-size recorded separately",
      serializedByteProjection: "raw-canonical-session-jsonl",
      ordering: "file order",
      normalization: "none",
      comparison: "per_fixture",
      phase: "rss_normal",
      expectedSource: "reference-oracle",
      owner: "classic SessionManager",
      limits: { items: null, bytes: null, concurrency: 1, spoolBytes: 0 },
    },
    {
      operation: "active-context-before",
      projection: "buildSessionContext",
      itemProjection: "active-context-message-count",
      serializedByteProjection: "stable-stringify-utf8:active-context-object",
      ordering: "compaction then kept and post-compaction messages",
      normalization: "recursively key-sorted UTF-8 JSON",
      comparison: "history_invariant",
      phase: "rss_normal",
      expectedSource: "reference-oracle",
      owner: "classic SessionManager",
      limits: { items: 5, bytes: 16384, concurrency: 1, spoolBytes: 0 },
    },
    {
      operation: "bounded-point-diagnostics",
      projection: "fixed IDs, label, snapshot, and branch edges",
      itemProjection: "fixed-point-descriptor-count",
      serializedByteProjection: "stable-stringify-utf8:16-canonical-point-descriptors-with-semantic-hashes",
      ordering: "fixed oracle ID order",
      normalization: "recursively key-sorted UTF-8 JSON",
      comparison: "history_invariant",
      phase: "rss_normal",
      expectedSource: "reference-oracle",
      owner: "B1 diagnostic",
      limits: { items: 16, bytes: 65536, concurrency: 1, spoolBytes: 0 },
    },
    {
      operation: "fixed-continuation",
      projection: "one user append, one assistant append, then buildSessionContext",
      itemProjection: "continuation-message-count",
      serializedByteProjection: "stable-stringify-utf8:{messages,activeContext}",
      ordering: "user then assistant",
      normalization: "generated wrapper IDs and timestamps excluded from context digest",
      comparison: "history_invariant",
      phase: "rss_normal",
      expectedSource: "reference-oracle",
      owner: "classic SessionManager",
      limits: { items: 2, bytes: 16384, concurrency: 1, spoolBytes: 0 },
    },
    {
      operation: "retained-ready",
      projection: "raw process memory and resource usage with session left open",
      itemProjection: "retained-ready-sample-count",
      serializedByteProjection: null,
      ordering: "three gc plus setImmediate turns",
      normalization: "none",
      comparison: "per_fixture",
      phase: "rss_normal",
      expectedSource: "diagnostic-observation",
      owner: "B1 diagnostic",
      limits: { items: 1, bytes: null, concurrency: 1, spoolBytes: 0 },
    },
  ],
};
check(exactJsonEqual(operations, expectedOperations), "operation table differs from the frozen B1 contract");
const operationByName = new Map(operations.rows.map((row) => [row.operation, row]));

function finiteOperationObservation(operation, itemsObserved, projection) {
  const row = operationByName.get(operation);
  check(row.limits.items !== null && itemsObserved === row.limits.items, `${operation} item observation differs from its exact cap`);
  const serializedBytesObserved = Buffer.byteLength(stableStringify(projection), "utf8");
  check(row.limits.bytes !== null && serializedBytesObserved <= row.limits.bytes, `${operation} serialized projection exceeds its byte cap`);
  return {
    itemsObserved,
    itemProjection: row.itemProjection,
    serializedBytesObserved,
    serializedByteProjection: row.serializedByteProjection,
    limits: row.limits,
    checks: { exactItems: true, serializedBytesWithinCap: true },
  };
}
check(sourceIdentity.schema === 1, "unsupported source identity");
check(Array.isArray(sourceIdentity.extensionManifest) && sourceIdentity.extensionManifest.length === 0, "source identity is not empty-gallery");
check(Array.isArray(sourceIdentity.downstreamPatches) && sourceIdentity.downstreamPatches.length === 0, "classic source has downstream patches");
check(crosswalk.schema === 1 && isObject(crosswalk.hashes) && isObject(crosswalk.runtime), "unsupported source crosswalk");
check(exactJsonEqual(extensionManifest, { extensions: [] }), "extension manifest must be exactly {extensions:[]}");
check(crosswalk.hashes.emptyExtensionManifest === extensionsInput.sha256, "crosswalk extension hash mismatch");

const commonPath = new URL("./common.mjs", import.meta.url).pathname;
const toolPaths = {
  common: commonPath,
  generator: args.generator,
  reference: args.reference,
  diagnostic: args.diagnostic,
  cappedCommand: new URL("./run-capped-command.mjs", import.meta.url).pathname,
  postflight: new URL("./record-postflight.mjs", import.meta.url).pathname,
  summary: new URL("./summarize-diagnostic.mjs", import.meta.url).pathname,
  seal: new URL("./seal-bundle.mjs", import.meta.url).pathname,
};
const tools = Object.fromEntries(
  Object.entries(toolPaths).map(([name, path]) => {
    const identity = hashFile(path, 65536, smallLimit);
    return [name, { path: resolve(path), ...identity }];
  }),
);
check(generation.tools?.generator?.sha256 === tools.generator.sha256, "generation used another generator");
check(generation.tools?.common?.sha256 === tools.common.sha256, "generation used another common module");
const runtimeExecutable = hashFile(process.execPath, 65536);
check(crosswalk.runtime.version === process.version, "reference runtime version differs from package build runtime");
check(crosswalk.runtime.executableSha256 === runtimeExecutable.sha256, "reference runtime executable differs from package build runtime");
check(generation.runtime?.executableSha256 === runtimeExecutable.sha256, "generation runtime drift");

function createRetainedFoldTracker(cap) {
  check(Number.isSafeInteger(cap) && cap > 0, "invalid retained-fold cap");
  let live = 0;
  let maxObserved = 0;

  const track = (hash, name) => {
    live += 1;
    maxObserved = Math.max(maxObserved, live);
    check(live <= cap, `retained incremental fold cap exceeded by ${name}`);
    let active = true;
    const fold = {
      update(value) {
        check(active, `retained incremental fold already finalized: ${name}`);
        hash.update(value);
        return fold;
      },
      copy() {
        check(active, `retained incremental fold already finalized: ${name}`);
        return track(hash.copy(), `${name}:copy`);
      },
      digest(encoding) {
        check(active, `retained incremental fold already finalized: ${name}`);
        active = false;
        try {
          return hash.digest(encoding);
        } finally {
          live -= 1;
        }
      },
    };
    return fold;
  };

  return {
    create(name) {
      return track(createHash("sha256"), name);
    },
    finish() {
      check(live === 0, "retained incremental folds remain live after reference import");
      return { cap, maxObserved, liveAfterImport: live };
    },
  };
}

const fixtureDir = realpathSync(args.fixtures);
const importLimits = spec.limits.referenceImport;
const scaleResults = [];
const invariantBefore = activeContextFromSpec(spec, false);
const invariantAfter = activeContextFromSpec(spec, true);
const invariantBeforeDigest = structuredSha256(invariantBefore);
const invariantAfterDigest = structuredSha256(invariantAfter);
const leftIds = new Set([spec.topology.leftChildId, spec.topology.leftLeafId]);
const headerBytes = Buffer.from(`${JSON.stringify(spec.header)}\n`, "utf8");
const headerOracle = {
  bytes: headerBytes.length,
  sha256: sha256(headerBytes),
  object: spec.header,
  objectSha256: structuredSha256(spec.header),
};
const invariantPointChecks = [spec.root, bulkLine(spec, 1).entry, ...spec.tail.slice(1)]
  .map((entry) => ({ id: entry.id, type: entry.type, parentId: entry.parentId, sha256: structuredSha256(entry) }))
  .sort((a, b) => compareUtf8(a.id, b.id));
const invariantPointMap = new Map(invariantPointChecks.map((point) => [point.id, point]));
const activeContextBeforeObservation = finiteOperationObservation(
  "active-context-before",
  invariantBefore.messages.length,
  invariantBefore,
);
const continuationMessages = [spec.continuation.userMessage, spec.continuation.assistantMessage];
const fixedContinuationObservation = finiteOperationObservation(
  "fixed-continuation",
  continuationMessages.length,
  { messages: continuationMessages, activeContext: invariantAfter },
);

for (const scale of spec.scales) {
  const generationRow = generation.fixtures.find((row) => row.scale === scale.name);
  check(generationRow !== undefined, `generation lacks ${scale.name}`);
  const path = resolve(fixtureDir, scale.file);
  check(resolve(path, "..") === fixtureDir, `fixture escapes directory: ${scale.file}`);
  const mode = lstatSync(path).mode & 0o777;
  check((mode & 0o222) === 0, `canonical fixture is writable: ${scale.file}`);

  const expectedTail = tailForScale(spec, scale.bulkEntries);
  const expectedLines = scale.bulkEntries + spec.tail.length + 2;
  const typeCounts = {};
  const foldTracker = createRetainedFoldTracker(importLimits.foldsRetained);
  const fullEdgeHash = foldTracker.create("full-edge-fold");
  const selectedEdgeHash = foldTracker.create("selected-edge-fold");
  const bulkPrefixHash = foldTracker.create("bulk-prefix-fold");
  const nestingPrefixHash = foldTracker.create("nesting-prefix-fold");
  const prefixCheckpoints = {};
  const nestingCheckpoints = {};
  const pointChecks = [];
  let nonHeaderEntries = 0;
  let maxConcurrentRecordRepresentations = 0;
  let maxLogicalRecordBytesRetained = 0;

  const streamed = streamJsonLines(path, importLimits, (line, lineNumber) => {
    let entry;
    try {
      entry = JSON.parse(line.toString("utf8"));
    } catch (error) {
      throw new Error(`invalid JSON at ${scale.file}:${lineNumber}: ${error.message}`);
    }
    check(isObject(entry), `non-object record at ${scale.file}:${lineNumber}`);
    let expected;
    let expectedRaw;
    let bulkIndex = 0;
    if (lineNumber === 1) {
      expected = spec.header;
      nestingPrefixHash.update(line).update("\n");
    } else if (lineNumber === 2) {
      expected = spec.root;
      nestingPrefixHash.update(line).update("\n");
    } else if (lineNumber <= scale.bulkEntries + 2) {
      bulkIndex = lineNumber - 2;
      const bulk = bulkLine(spec, bulkIndex);
      expected = bulk.entry;
      expectedRaw = bulk.line.subarray(0, bulk.line.length - 1);
      check(line.length + 1 === bulk.line.length && Buffer.compare(line, expectedRaw) === 0, `bulk bytes drift at ${scale.name}:${bulkIndex}`);
      bulkPrefixHash.update(line).update("\n");
      nestingPrefixHash.update(line).update("\n");
      const checkpoint = spec.scales.find((candidate) => candidate.bulkEntries === bulkIndex);
      if (checkpoint) {
        prefixCheckpoints[checkpoint.name] = bulkPrefixHash.copy().digest("hex");
        nestingCheckpoints[checkpoint.name] = nestingPrefixHash.copy().digest("hex");
      }
    } else {
      const tailIndex = lineNumber - scale.bulkEntries - 3;
      expected = expectedTail[tailIndex];
      check(expected !== undefined, `unexpected extra record in ${scale.file}`);
    }
    const canonical = expectedRaw ?? Buffer.from(JSON.stringify(expected), "utf8");
    maxConcurrentRecordRepresentations = Math.max(maxConcurrentRecordRepresentations, 2);
    maxLogicalRecordBytesRetained = Math.max(maxLogicalRecordBytesRetained, line.length + canonical.length + 2);
    check(Buffer.compare(line, canonical) === 0, `non-canonical record at ${scale.file}:${lineNumber}`);
    if (bulkIndex === 0) check(exactJsonEqual(entry, expected), `record value drift at ${scale.file}:${lineNumber}`);

    if (lineNumber > 1) {
      nonHeaderEntries += 1;
      increment(typeCounts, entry.type);
      updateStructuredFold(fullEdgeHash, edgeOf(entry));
      if (!leftIds.has(entry.id)) updateStructuredFold(selectedEdgeHash, edgeOf(entry));
      const invariantPoint = invariantPointMap.get(entry.id);
      if (invariantPoint) {
        check(structuredSha256(entry) === invariantPoint.sha256, `invariant point drift: ${entry.id}`);
      }
      if (bulkIndex === scale.bulkEntries || entry.id === spec.tail[0].id) {
        pointChecks.push({ id: entry.id, type: entry.type, parentId: entry.parentId, sha256: structuredSha256(entry) });
      }
    }
  }, (name) => foldTracker.create(name));

  check(streamed.lines === expectedLines, `line count drift for ${scale.name}`);
  check(maxConcurrentRecordRepresentations <= importLimits.maxConcurrentRecordRepresentations, "reference record-representation cap exceeded");
  check(maxLogicalRecordBytesRetained <= importLimits.maxLogicalRecordBytesRetained, "reference logical record-byte cap exceeded");
  check(nonHeaderEntries === expectedLines - 1, `entry count drift for ${scale.name}`);
  check(exactJsonEqual(typeCounts, expectedTypeCounts(spec, scale.bulkEntries)), `type count drift for ${scale.name}`);
  check(streamed.maxLineBytes === spec.bulk.recordBytes, `bulk line limit was not exercised for ${scale.name}`);
  check(streamed.bytes === generationRow.bytes && streamed.sha256 === generationRow.sha256, `generation hash/count mismatch for ${scale.name}`);
  check(nonHeaderEntries === generationRow.nonHeaderEntries && streamed.lines === generationRow.fileEntries, `generation entry mismatch for ${scale.name}`);
  check(exactJsonEqual(typeCounts, generationRow.typeCounts), `generation type mismatch for ${scale.name}`);
  check(prefixCheckpoints[scale.name] === generationRow.bulkSha256, `generation bulk fold mismatch for ${scale.name}`);
  check(nestingCheckpoints[scale.name] === generationRow.nestingSha256, `generation nesting fold mismatch for ${scale.name}`);
  check(pointChecks.length === 2, "scale point-read set drift");
  check(
    pointChecks.length + invariantPointChecks.length <= spec.limits.diagnosticPreflight.maxPointEntriesRetained,
    "combined point-read set exceeds diagnostic cap",
  );
  const fullEdgeFoldSha256 = fullEdgeHash.digest("hex");
  const selectedPathEdgeFoldSha256 = selectedEdgeHash.digest("hex");
  const finalBulkPrefixSha256 = bulkPrefixHash.digest("hex");
  const finalNestingPrefixSha256 = nestingPrefixHash.digest("hex");
  check(finalBulkPrefixSha256 === prefixCheckpoints[scale.name], `final bulk fold mismatch for ${scale.name}`);
  check(finalNestingPrefixSha256 === nestingCheckpoints[scale.name], `final nesting fold mismatch for ${scale.name}`);
  const retainedIncrementalFolds = foldTracker.finish();

  const beforeFileEntries = streamed.lines;
  const beforeById = nonHeaderEntries;
  const beforeTypes = typeCounts;
  const afterTypes = { ...typeCounts, message: typeCounts.message + 2 };
  const snapshot = expectedTail.find((entry) => entry.id === spec.topology.snapshotEntryId);
  const label = expectedTail.find((entry) => entry.id === spec.topology.labelEntryId);
  const activeLeaf = expectedTail.find((entry) => entry.id === spec.topology.selectedLeafId);
  const scalePointChecks = pointChecks.sort((a, b) => compareUtf8(a.id, b.id));
  const diagnosticPointDescriptors = [...invariantPointChecks, ...scalePointChecks];
  check(new Set(diagnosticPointDescriptors.map((point) => point.id)).size === diagnosticPointDescriptors.length, "duplicate point-diagnostic descriptor");
  const pointDiagnosticObservation = finiteOperationObservation(
    "bounded-point-diagnostics",
    diagnosticPointDescriptors.length,
    diagnosticPointDescriptors,
  );
  const classicOpenRow = operationByName.get("classic-open");
  const retainedReadyRow = operationByName.get("retained-ready");
  const operationObservations = {
    "classic-open": {
      itemsObserved: beforeFileEntries,
      itemProjection: classicOpenRow.itemProjection,
      secondaryItemsObserved: { byId: beforeById },
      serializedBytesObserved: streamed.bytes,
      serializedByteProjection: classicOpenRow.serializedByteProjection,
      limits: classicOpenRow.limits,
      checks: { intentionallyUnboundedItems: true, intentionallyUnboundedBytes: true },
    },
    "active-context-before": activeContextBeforeObservation,
    "bounded-point-diagnostics": pointDiagnosticObservation,
    "fixed-continuation": fixedContinuationObservation,
    "retained-ready": {
      itemsObserved: null,
      itemsRequired: retainedReadyRow.limits.items,
      itemProjection: retainedReadyRow.itemProjection,
      serializedBytesObserved: null,
      serializedByteProjection: retainedReadyRow.serializedByteProjection,
      limits: retainedReadyRow.limits,
      enforcement: "summary-exactly-one-retained-ready-sample",
    },
  };

  const accumulatedScalePointDescriptors =
    scaleResults.reduce((total, result) => total + result.pointChecks.length, 0) + scalePointChecks.length;
  const entryAndPointDescriptorAccounting = {
    cap: importLimits.maxEntryAndPointDescriptorObjectsLive,
    specTailEntries: spec.tail.length,
    currentExpectedTailEntries: expectedTail.length,
    invariantPointDescriptors: invariantPointChecks.length,
    accumulatedScalePointDescriptors,
    fixedHeaderAndRootTemplates: 2,
    currentParsedAndExpectedRecords: 2,
  };
  entryAndPointDescriptorAccounting.total = Object.entries(entryAndPointDescriptorAccounting)
    .filter(([name]) => !["cap", "total"].includes(name))
    .reduce((total, [, count]) => total + count, 0);
  check(
    entryAndPointDescriptorAccounting.total <= entryAndPointDescriptorAccounting.cap,
    "reference entry/point-descriptor live-object cap exceeded",
  );
  const scaleResultOracleGraphAccounting = {
    cap: importLimits.maxScaleResultOracleGraphsLive,
    priorScaleResultOracleGraphs: scaleResults.length,
    currentScaleResultOracleGraphUnderConstruction: 1,
    total: scaleResults.length + 1,
  };
  check(
    scaleResultOracleGraphAccounting.total <= scaleResultOracleGraphAccounting.cap,
    "reference scale-result oracle graph cap exceeded",
  );

  const scaleResult = {
    scale: scale.name,
    bulkEntries: scale.bulkEntries,
    canonical: { file: scale.file, bytes: streamed.bytes, sha256: streamed.sha256 },
    prepared: { kind: "byte-identical-disposable-copy", bytes: streamed.bytes, sha256: streamed.sha256 },
    prefixCheckpoints,
    nestingCheckpoints,
    before: {
      fileEntries: beforeFileEntries,
      byId: beforeById,
      nonHeaderEntries,
      typeCounts: beforeTypes,
      fullEdgeFoldSha256,
      selectedPathEdgeFoldSha256,
      activeContext: invariantBefore,
      activeContextSha256: invariantBeforeDigest,
      model: invariantBefore.model,
      thinkingLevel: invariantBefore.thinkingLevel,
      activeLeaf: { id: activeLeaf.id, sha256: structuredSha256(activeLeaf) },
    },
    after: {
      fileEntries: beforeFileEntries + 2,
      byId: beforeById + 2,
      nonHeaderEntries: nonHeaderEntries + 2,
      typeCounts: afterTypes,
      activeContext: invariantAfter,
      activeContextSha256: invariantAfterDigest,
      model: invariantAfter.model,
      thinkingLevel: invariantAfter.thinkingLevel,
      activeLeaf: {
        kind: "appended-assistant",
        parentKind: "appended-user",
        messageSha256: structuredSha256(spec.continuation.assistantMessage),
      },
    },
    pointChecks: scalePointChecks,
    branch: {
      pointId: spec.topology.branchPointId,
      children: [spec.topology.leftChildId, spec.topology.rightChildId],
      leftLeafId: spec.topology.leftLeafId,
      rightLeafId: spec.topology.rightLeafId,
      selectedActiveLeafId: spec.topology.selectedLeafId,
    },
    label: {
      entryId: label.id,
      targetId: label.targetId,
      value: label.label,
      entrySha256: structuredSha256(label),
    },
    snapshot: {
      entryId: snapshot.id,
      customType: snapshot.customType,
      entrySha256: structuredSha256(snapshot),
      dataSha256: structuredSha256(snapshot.data),
    },
    operationObservations,
    limitsObserved: {
      maxLineBytes: streamed.maxLineBytes,
      chunkBytes: importLimits.chunkBytes,
      maxOpenFiles: 1,
      maxEntryAndPointDescriptorObjectsLive: entryAndPointDescriptorAccounting.total,
      maxScaleResultOracleGraphsLive: scaleResultOracleGraphAccounting.total,
      maxConcurrentRecordRepresentations,
      maxLogicalRecordBytesRetained,
      retainedIncrementalFolds,
      diagnosticPointChecks: pointChecks.length + invariantPointChecks.length,
      entryAndPointDescriptorAccounting,
      scaleResultOracleGraphAccounting,
      pagesRetained: 0,
      cleanup: { descriptorClosed: true, pendingLineBytes: 0 },
    },
  };
  scaleResults.push(scaleResult);
}

for (let index = 1; index < scaleResults.length; index += 1) {
  const smaller = scaleResults[index - 1];
  const larger = scaleResults[index];
  check(larger.canonical.bytes >= smaller.canonical.bytes * 3, "fixture bytes do not grow by at least 3x");
  check(larger.before.nonHeaderEntries >= smaller.before.nonHeaderEntries * 3, "fixture entries do not grow by at least 3x");
}
for (const larger of scaleResults) {
  for (const smaller of scaleResults.filter((candidate) => candidate.bulkEntries <= larger.bulkEntries)) {
    check(larger.prefixCheckpoints[smaller.scale] === smaller.prefixCheckpoints[smaller.scale], `bulk prefix mismatch: ${smaller.scale}/${larger.scale}`);
    check(larger.nestingCheckpoints[smaller.scale] === smaller.nestingCheckpoints[smaller.scale], `nesting prefix mismatch: ${smaller.scale}/${larger.scale}`);
  }
  check(larger.before.activeContextSha256 === invariantBeforeDigest, "before context is not invariant");
  check(larger.after.activeContextSha256 === invariantAfterDigest, "after context is not invariant");
}

const manifest = {
  schema: 1,
  kind: "pi-b1-classic-fixture-manifest",
  qualification: "descriptive-b1-only",
  sessionVersion: spec.sessionVersion,
  sessionHeader: headerOracle,
  structuredEncoding: "recursive-key-sorted-utf8-json-v1",
  foldEncoding: "uint64be-length-plus-structured-json-v1",
  exactStreamEncoding: "raw-bytes-sha256",
  inputs: {
    spec: { bytes: specInput.bytes, sha256: specInput.sha256 },
    generation: { bytes: generationInput.bytes, sha256: generationInput.sha256 },
    operations: { bytes: operationsInput.bytes, sha256: operationsInput.sha256 },
    sourceIdentity: { bytes: sourceInput.bytes, sha256: sourceInput.sha256 },
    sourceCrosswalk: { bytes: crosswalkInput.bytes, sha256: crosswalkInput.sha256 },
  },
  tools,
  runtime: {
    executable: process.execPath,
    executableSha256: runtimeExecutable.sha256,
    version: process.version,
    platform: process.platform,
    arch: process.arch,
  },
  package: {
    source: sourceIdentity,
    hashes: crosswalk.hashes,
    buildRuntime: crosswalk.runtime,
    sourceMap: crosswalk.sourceMap,
    causalLocations: crosswalk.causalLocations,
  },
  extensions: {
    manifest: extensionManifest,
    bytes: extensionsInput.bytes,
    sha256: extensionsInput.sha256,
  },
  limits: {
    generator: spec.limits.generator,
    import: spec.limits.referenceImport,
    copy: spec.limits.copy,
    diagnosticPreflight: spec.limits.diagnosticPreflight,
    cappedCommand: spec.limits.cappedCommand,
    postflight: spec.limits.postflight,
    seal: spec.limits.seal,
    smallJsonBytes: spec.limits.smallJsonBytes,
    bundleWrite: { maxOpenFiles: 1, temporaryFiles: 1, noClobberHardLink: true },
    referenceRetention: {
      entryAndPointDescriptorObjects: {
        cap: importLimits.maxEntryAndPointDescriptorObjectsLive,
        maxObserved: Math.max(...scaleResults.map((result) => result.limitsObserved.maxEntryAndPointDescriptorObjectsLive)),
      },
      scaleResultOracleGraphs: {
        cap: importLimits.maxScaleResultOracleGraphsLive,
        maxObserved: Math.max(...scaleResults.map((result) => result.limitsObserved.maxScaleResultOracleGraphsLive)),
      },
      maxConcurrentRecordRepresentationsObserved: Math.max(...scaleResults.map((result) => result.limitsObserved.maxConcurrentRecordRepresentations)),
      maxLogicalRecordBytesObserved: Math.max(...scaleResults.map((result) => result.limitsObserved.maxLogicalRecordBytesRetained)),
      retainedIncrementalFolds: {
        cap: importLimits.foldsRetained,
        maxObserved: Math.max(...scaleResults.map((result) => result.limitsObserved.retainedIncrementalFolds.maxObserved)),
        liveAfterEveryImport: scaleResults.every((result) => result.limitsObserved.retainedIncrementalFolds.liveAfterImport === 0),
      },
    },
  },
  operations: { schema: operations.schema, sha256: operationsInput.sha256, rows: operations.rows },
  fixtures: scaleResults.map((result) => ({
    scale: result.scale,
    bulkEntries: result.bulkEntries,
    canonical: result.canonical,
    prepared: result.prepared,
    fileEntries: result.before.fileEntries,
    nonHeaderEntries: result.before.nonHeaderEntries,
    typeCounts: result.before.typeCounts,
    operationObservations: result.operationObservations,
  })),
};

const oracles = {
  schema: 1,
  kind: "pi-b1-classic-reference-oracles",
  qualification: "descriptive-b1-only",
  manifestObjectSha256: structuredSha256(manifest),
  specSha256: specInput.sha256,
  operationsSha256: operationsInput.sha256,
  tools,
  limits: {
    copy: spec.limits.copy,
    postflight: spec.limits.postflight,
    seal: spec.limits.seal,
    cappedCommand: spec.limits.cappedCommand,
    smallJsonBytes: spec.limits.smallJsonBytes,
  },
  continuation: {
    userMessage: spec.continuation.userMessage,
    userMessageSha256: structuredSha256(spec.continuation.userMessage),
    assistantMessage: spec.continuation.assistantMessage,
    assistantMessageSha256: structuredSha256(spec.continuation.assistantMessage),
  },
  invariant: {
    before: { object: invariantBefore, sha256: invariantBeforeDigest },
    after: { object: invariantAfter, sha256: invariantAfterDigest },
  },
  header: headerOracle,
  invariantPointChecks,
  fixtures: Object.fromEntries(scaleResults.map((result) => [result.scale, result])),
};

writeJsonAtomic(args.manifest, manifest);
writeJsonAtomic(args.oracles, oracles);
