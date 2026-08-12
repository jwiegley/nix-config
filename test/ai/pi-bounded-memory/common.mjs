import { createHash } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants,
  existsSync,
  fstatSync,
  fsyncSync,
  lstatSync,
  linkSync,
  openSync,
  readSync,
  unlinkSync,
  writeSync,
} from "node:fs";
import { basename, dirname, resolve } from "node:path";

export function fail(message) {
  throw new Error(message);
}

export function check(condition, message) {
  if (!condition) fail(message);
}

export function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function compareUtf8(a, b) {
  return Buffer.compare(Buffer.from(a), Buffer.from(b));
}

export function sortedJsonValue(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    check(Number.isFinite(value), "structured JSON contains a non-finite number");
    return Object.is(value, -0) ? 0 : value;
  }
  if (Array.isArray(value)) return value.map(sortedJsonValue);
  check(isObject(value), "structured JSON contains an unsupported value");
  const output = {};
  for (const key of Object.keys(value).sort(compareUtf8)) {
    check(value[key] !== undefined, `structured JSON contains undefined at ${key}`);
    output[key] = sortedJsonValue(value[key]);
  }
  return output;
}

export function stableStringify(value) {
  return JSON.stringify(sortedJsonValue(value));
}

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function structuredSha256(value) {
  return sha256(Buffer.from(stableStringify(value), "utf8"));
}

function openRegular(path) {
  const before = lstatSync(path);
  check(before.isFile() && !before.isSymbolicLink(), `not a regular file: ${path}`);
  const noFollow = constants.O_NOFOLLOW ?? 0;
  const fd = openSync(path, constants.O_RDONLY | noFollow);
  let info;
  try {
    info = fstatSync(fd);
  } catch (error) {
    closeSync(fd);
    throw error;
  }
  if (!info.isFile() || info.dev !== before.dev || info.ino !== before.ino) {
    closeSync(fd);
    fail(`file changed while opening: ${path}`);
  }
  return { fd, info };
}

export function hashFile(path, chunkBytes = 65536, maxBytes = Number.MAX_SAFE_INTEGER) {
  check(Number.isSafeInteger(chunkBytes) && chunkBytes > 0, "invalid hash chunk limit");
  const { fd, info } = openRegular(path);
  const hash = createHash("sha256");
  const buffer = Buffer.allocUnsafe(chunkBytes);
  let bytes = 0;
  let after;
  try {
    check(info.size <= maxBytes, `file exceeds ${maxBytes} bytes: ${path}`);
    for (;;) {
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (count === 0) break;
      bytes += count;
      check(bytes <= maxBytes, `file exceeds ${maxBytes} bytes: ${path}`);
      hash.update(buffer.subarray(0, count));
    }
  } finally {
    try {
      after = fstatSync(fd);
    } finally {
      closeSync(fd);
    }
  }
  check(after.size === info.size && after.mtimeMs === info.mtimeMs && after.ctimeMs === info.ctimeMs, `file changed while hashing: ${path}`);
  check(bytes === info.size, `file changed while hashing: ${path}`);
  return { bytes, sha256: hash.digest("hex") };
}

export function readJson(path, maxBytes = 16777216) {
  check(Number.isSafeInteger(maxBytes) && maxBytes > 0, "invalid JSON byte limit");
  const { fd, info } = openRegular(path);
  let bytes;
  const hash = createHash("sha256");
  let offset = 0;
  let after;
  try {
    check(Number.isSafeInteger(info.size) && info.size <= maxBytes, `file exceeds ${maxBytes} bytes: ${path}`);
    bytes = Buffer.allocUnsafe(info.size);
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      check(count > 0, `file shortened while reading: ${path}`);
      hash.update(bytes.subarray(offset, offset + count));
      offset += count;
    }
    const extra = Buffer.allocUnsafe(1);
    check(readSync(fd, extra, 0, 1, null) === 0, `file grew while reading: ${path}`);
  } finally {
    try {
      after = fstatSync(fd);
    } finally {
      closeSync(fd);
    }
  }
  check(after.size === info.size && after.mtimeMs === info.mtimeMs && after.ctimeMs === info.ctimeMs, `file changed while reading: ${path}`);
  const identity = { bytes: offset, sha256: hash.digest("hex") };
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    const failure = new Error(`invalid JSON in ${path}: ${error.message}`);
    failure.identity = identity;
    throw failure;
  }
  if (!isObject(value)) {
    const failure = new Error(`top-level JSON must be an object: ${path}`);
    failure.identity = identity;
    throw failure;
  }
  return { value, ...identity };
}

export function parseArgs(argv, names) {
  check(argv.length === names.length * 2, `expected exactly ${names.map((n) => `--${n} VALUE`).join(" ")}`);
  const allowed = new Set(names);
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    check(flag.startsWith("--") && allowed.has(flag.slice(2)), `unknown option: ${flag}`);
    const name = flag.slice(2);
    check(!(name in result), `duplicate option: ${flag}`);
    check(typeof value === "string" && value.length > 0, `missing value for ${flag}`);
    result[name] = value;
  }
  for (const name of names) check(name in result, `missing --${name}`);
  return result;
}

function writeAll(fd, bytes) {
  let offset = 0;
  while (offset < bytes.length) {
    const count = writeSync(fd, bytes, offset, bytes.length - offset);
    check(count > 0, "output write made no progress");
    offset += count;
  }
}

export function atomicOutputPaths(path) {
  const target = resolve(path);
  return { target, temp: `${target}.tmp-${process.pid}` };
}

export function planAtomicOutputs(paths) {
  const plan = paths.map(atomicOutputPaths);
  const names = plan.flatMap(({ target, temp }) => [target, temp]);
  check(new Set(names).size === names.length, "output targets and derived temporary paths must all differ");
  return plan;
}

export function tempFileIdentity(fd) {
  const info = fstatSync(fd);
  check(info.isFile(), "temporary output is not a regular file");
  return { dev: info.dev, ino: info.ino };
}

function checkOwnedTemp(path, identity) {
  const info = lstatSync(path);
  check(
    info.isFile() &&
      !info.isSymbolicLink() &&
      info.dev === identity.dev &&
      info.ino === identity.ino,
    `refusing to operate on replaced temporary output: ${path}`,
  );
}

export function unlinkOwnedTemp(path, identity) {
  try {
    checkOwnedTemp(path, identity);
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
  unlinkSync(path);
  return true;
}

export function publishNoClobber(temp, target, identity = undefined) {
  if (identity !== undefined) checkOwnedTemp(temp, identity);
  linkSync(temp, target);
  if (identity === undefined) {
    unlinkSync(temp);
  } else {
    check(unlinkOwnedTemp(temp, identity), `temporary output disappeared during publication: ${temp}`);
  }
}

export function writeJsonAtomic(path, value, mode = 0o444) {
  const { target, temp } = atomicOutputPaths(path);
  check(!existsSync(target), `refusing to replace existing output: ${target}`);
  const parent = dirname(target);
  const parentInfo = lstatSync(parent);
  check(parentInfo.isDirectory() && !parentInfo.isSymbolicLink(), `invalid output directory: ${parent}`);
  let fd;
  let identity;
  try {
    fd = openSync(temp, "wx", 0o600);
    identity = tempFileIdentity(fd);
    const bytes = Buffer.from(`${JSON.stringify(sortedJsonValue(value), null, 2)}\n`, "utf8");
    writeAll(fd, bytes);
    fsyncSync(fd);
    const openFd = fd;
    fd = undefined;
    closeSync(openFd);
    chmodSync(temp, mode);
    publishNoClobber(temp, target, identity);
    return { bytes: bytes.length, sha256: sha256(bytes) };
  } catch (error) {
    const cleanupErrors = [];
    if (fd !== undefined) {
      const openFd = fd;
      fd = undefined;
      try {
        closeSync(openFd);
      } catch (cleanupError) {
        cleanupErrors.push(cleanupError);
      }
    }
    if (identity !== undefined) {
      try {
        unlinkOwnedTemp(temp, identity);
      } catch (cleanupError) {
        cleanupErrors.push(cleanupError);
      }
    }
    if (cleanupErrors.length > 0) {
      throw new AggregateError([error, ...cleanupErrors], `atomic JSON output cleanup failed: ${target}`);
    }
    throw error;
  }
}

export function bulkId(spec, oneBasedIndex) {
  check(Number.isInteger(oneBasedIndex) && oneBasedIndex > 0, "invalid bulk index");
  const digits = String(oneBasedIndex).padStart(spec.bulk.idWidth, "0");
  check(digits.length === spec.bulk.idWidth, "bulk index exceeds fixed ID width");
  return `${spec.bulk.idPrefix}${digits}`;
}

export function bulkLine(spec, oneBasedIndex) {
  const id = bulkId(spec, oneBasedIndex);
  const entry = {
    type: "message",
    id,
    parentId: oneBasedIndex === 1 ? spec.root.id : bulkId(spec, oneBasedIndex - 1),
    timestamp: spec.bulk.timestamp,
    message: {
      role: "user",
      content: [{ type: "text", text: "" }],
      timestamp: spec.bulk.messageTimestamp,
    },
  };
  const emptyBytes = Buffer.byteLength(JSON.stringify(entry), "utf8") + 1;
  const contentBytes = spec.bulk.recordBytes - emptyBytes;
  const prefix = `${spec.seed}/${id}/`;
  check(contentBytes >= Buffer.byteLength(prefix), "bulk record cannot fit its deterministic prefix");
  const digestByte = createHash("sha256").update(`${spec.seed}:${id}`).digest()[0];
  const fill = spec.bulk.payloadAlphabet[digestByte % spec.bulk.payloadAlphabet.length];
  entry.message.content[0].text = prefix + fill.repeat(contentBytes - prefix.length);
  const line = Buffer.from(`${JSON.stringify(entry)}\n`, "utf8");
  check(line.length === spec.bulk.recordBytes, `bulk record ${id} is ${line.length} bytes`);
  return { entry, line };
}

export function tailForScale(spec, bulkEntries) {
  const lastId = bulkId(spec, bulkEntries);
  return spec.tail.map((entry, index) =>
    index === 0 ? { ...entry, parentId: lastId } : JSON.parse(JSON.stringify(entry)),
  );
}

export function increment(counts, type) {
  counts[type] = (counts[type] ?? 0) + 1;
}

export function expectedTypeCounts(spec, bulkEntries) {
  const counts = {};
  increment(counts, spec.root.type);
  counts.message += bulkEntries;
  for (const entry of spec.tail) increment(counts, entry.type);
  return counts;
}

export function updateStructuredFold(hash, value) {
  const bytes = Buffer.from(stableStringify(value), "utf8");
  const length = Buffer.allocUnsafe(8);
  length.writeBigUInt64BE(BigInt(bytes.length));
  hash.update(length);
  hash.update(bytes);
}

export function edgeOf(entry) {
  return { id: entry.id, parentId: entry.parentId, type: entry.type };
}

export function streamJsonLines(path, limits, onLine, createFold) {
  check(typeof createFold === "function", "retained fold factory is required");
  check(Number.isSafeInteger(limits.chunkBytes) && limits.chunkBytes > 0, "invalid stream chunk limit");
  check(Number.isSafeInteger(limits.maxLineBytes) && limits.maxLineBytes > 0, "invalid line limit");
  const { fd, info } = openRegular(path);
  const buffer = Buffer.allocUnsafe(limits.chunkBytes);
  const fileHash = createFold("stream-file-sha256");
  let pending = null;
  let bytes = 0;
  let lines = 0;
  let maxLineBytes = 0;
  let after;
  try {
    for (;;) {
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (count === 0) break;
      const chunk = buffer.subarray(0, count);
      bytes += count;
      fileHash.update(chunk);
      let start = 0;
      for (;;) {
        const newline = chunk.indexOf(10, start);
        if (newline < 0) break;
        const fragment = chunk.subarray(start, newline);
        let line;
        if (pending !== null) {
          check(pending.length + fragment.length + 1 <= limits.maxLineBytes, `line exceeds cap in ${path}`);
          line = Buffer.concat([pending, fragment], pending.length + fragment.length);
          pending = null;
        } else {
          check(fragment.length + 1 <= limits.maxLineBytes, `line exceeds cap in ${path}`);
          line = fragment;
        }
        lines += 1;
        maxLineBytes = Math.max(maxLineBytes, line.length + 1);
        onLine(line, lines);
        start = newline + 1;
      }
      const remainder = chunk.subarray(start);
      if (remainder.length > 0) {
        const length = (pending?.length ?? 0) + remainder.length;
        check(length < limits.maxLineBytes, `unterminated line reaches cap in ${path}`);
        pending = pending === null ? Buffer.from(remainder) : Buffer.concat([pending, remainder], length);
      }
    }
  } finally {
    try {
      after = fstatSync(fd);
    } finally {
      closeSync(fd);
    }
  }
  check(after.size === info.size && after.mtimeMs === info.mtimeMs && after.ctimeMs === info.ctimeMs, `fixture changed while streaming: ${path}`);
  check(pending === null, `fixture is not LF-terminated: ${path}`);
  check(bytes === info.size, `fixture changed while streaming: ${path}`);
  return { bytes, sha256: fileHash.digest("hex"), lines, maxLineBytes, lfTerminated: true };
}

export function activeContextFromSpec(spec, includeContinuation = false) {
  const byId = new Map(spec.tail.map((entry) => [entry.id, entry]));
  const compaction = byId.get(spec.topology.compactionEntryId);
  const keptUser = byId.get(spec.topology.firstKeptEntryId);
  const keptAssistant = byId.get("tail-kept-assistant-v1");
  const postUser = byId.get("tail-post-user-v1");
  const postAssistant = byId.get(spec.topology.selectedLeafId);
  const thinking = byId.get("tail-thinking-v1");
  for (const entry of [compaction, keptUser, keptAssistant, postUser, postAssistant, thinking]) {
    check(entry !== undefined, "spec lacks an active-context entry");
  }
  const messages = [
    {
      role: "compactionSummary",
      summary: compaction.summary,
      tokensBefore: compaction.tokensBefore,
      timestamp: Date.parse(compaction.timestamp),
    },
    keptUser.message,
    keptAssistant.message,
    postUser.message,
    postAssistant.message,
  ];
  if (includeContinuation) messages.push(spec.continuation.userMessage, spec.continuation.assistantMessage);
  return JSON.parse(
    JSON.stringify({
      messages,
      thinkingLevel: thinking.thinkingLevel,
      model: { provider: postAssistant.message.provider, modelId: postAssistant.message.model },
    }),
  );
}

export function validateSpec(spec) {
  check(spec.schema === 1 && spec.kind === "pi-b1-fixture-spec", "unsupported fixture spec");
  check(spec.qualification === "descriptive-b1-only", "fixture spec qualification drift");
  check(spec.sessionVersion === 3 && spec.header?.version === 3 && spec.header?.type === "session", "session version drift");
  check(spec.header.id === "pi-b1-session-v1" && spec.root?.id === "root-user-v1", "fixed root identity drift");
  check(spec.root.type === "message" && spec.root.parentId === null, "invalid fixed root");
  check(typeof spec.seed === "string" && /^[\x20-\x7e]+$/.test(spec.seed), "invalid public seed");
  const expectedScales = [["16m", 512], ["64m", 2048], ["256m", 8192], ["1g", 32768]];
  check(Array.isArray(spec.scales) && spec.scales.length === expectedScales.length, "scale table drift");
  for (let i = 0; i < expectedScales.length; i += 1) {
    const scale = spec.scales[i];
    check(scale.name === expectedScales[i][0] && scale.bulkEntries === expectedScales[i][1], "scale identity drift");
    check(typeof scale.file === "string" && basename(scale.file) === scale.file && scale.file.endsWith(".jsonl"), "unsafe fixture filename");
  }
  check(spec.bulk?.recordBytes === 32768 && spec.bulk.idWidth === 5, "bulk format drift");
  check(typeof spec.bulk.payloadAlphabet === "string" && spec.bulk.payloadAlphabet.length >= 2, "invalid bulk alphabet");
  check(exactJsonEqual(spec.limits?.generator, {
    maxRecordBytes: 32768,
    hashChunkBytes: 65536,
    maxOpenFiles: 1,
    maxBulkEntryRecordsRetained: 1,
    maxFixturesRetained: 0,
  }), "generator limits drift");
  check(exactJsonEqual(spec.limits?.referenceImport, {
    maxLineBytes: 32768,
    chunkBytes: 65536,
    maxOpenFiles: 1,
    maxEntryAndPointDescriptorObjectsLive: 64,
    maxScaleResultOracleGraphsLive: 4,
    maxConcurrentRecordRepresentations: 2,
    maxLogicalRecordBytesRetained: 65536,
    foldsRetained: 6,
  }), "reference limits drift");
  check(exactJsonEqual(spec.limits?.copy, {
    schema: 1,
    implementation: "gnu-coreutils-cp",
    executableBinding: "exact-launcher-symlink-and-resolved-file-identity",
    argv: ["cp", "--reflink=never", "fixture:<endpoint>", "namespace:session.jsonl"],
    destinationMode: "0600",
    opaqueImplementationInternalsClaimed: false,
    postflightVerification: "full-prefix-bytes-and-sha256",
  }), "copy policy drift");
  check(exactJsonEqual(spec.limits?.diagnosticPreflight, {
    maxHeaderBytes: 4096,
    maxOpenFiles: 1,
    maxPointEntriesRetained: 16,
  }), "diagnostic limits drift");
  check(exactJsonEqual(spec.limits?.cappedCommand, {
    maxBytesPerStream: 16777216,
    maxArgumentCount: 64,
    maxArgumentBytes: 65536,
    maxArgumentBytesPerArgument: 4096,
    maxOpenSinkFiles: 2,
    maxTemporaryStreamFiles: 2,
    maxReservedResultFiles: 1,
    signalGraceMilliseconds: 1000,
  }), "capped-command limits drift");
  check(exactJsonEqual(spec.limits?.postflight, {
    hashChunkBytes: 65536,
    maxOpenFiles: 1,
    maxSuffixBytes: 1048576,
    maxCopyLauncherTargetBytes: 1024,
    maxCopyExecutableBytes: 16777216,
    maxSmallJsonBytes: 16777216,
  }), "postflight limits drift");
  check(exactJsonEqual(spec.limits?.seal, {
    hashChunkBytes: 65536,
    maxEntries: 512,
    maxFiles: 256,
    maxOpenDirectories: 9,
    maxDepth: 8,
    maxRelativePathBytes: 1024,
    maxTotalPathBytes: 65536,
    maxChecksumBytes: 131072,
  }), "seal limits drift");
  check(spec.limits?.smallJsonBytes === 16777216, "small-JSON limit drift");
  check(Array.isArray(spec.tail) && spec.tail.length === 13, "fixed tail length drift");
  const ids = [spec.root.id, ...spec.tail.map((entry) => entry.id)];
  check(new Set(ids).size === ids.length, "duplicate fixed IDs");
  const t = Object.fromEntries(spec.tail.map((entry) => [entry.id, entry]));
  check(spec.tail[0].parentId === spec.tailParentPlaceholder, "first tail parent placeholder drift");
  check(t["tail-thinking-v1"]?.parentId === "tail-model-v1", "thinking edge drift");
  check(t["tail-left-user-v1"]?.parentId === "tail-thinking-v1", "left branch edge drift");
  check(t["tail-left-assistant-v1"]?.parentId === "tail-left-user-v1", "left leaf edge drift");
  check(t["tail-right-user-v1"]?.parentId === "tail-thinking-v1", "right branch edge drift");
  check(t["tail-right-assistant-v1"]?.parentId === "tail-right-user-v1", "right leaf edge drift");
  check(t["tail-snapshot-v1"]?.type === "custom" && t["tail-snapshot-v1"].parentId === "tail-right-assistant-v1", "snapshot drift");
  check(t["tail-left-label-v1"]?.type === "label" && t["tail-left-label-v1"].targetId === "tail-left-assistant-v1", "label drift");
  check(t["tail-kept-user-v1"]?.parentId === "tail-left-label-v1", "kept user edge drift");
  check(t["tail-kept-assistant-v1"]?.parentId === "tail-kept-user-v1", "kept assistant edge drift");
  check(t["tail-compaction-v1"]?.firstKeptEntryId === "tail-kept-user-v1", "compaction kept ID drift");
  check(t["tail-post-user-v1"]?.parentId === "tail-compaction-v1", "post-compaction user edge drift");
  check(t["tail-post-assistant-v1"]?.parentId === "tail-post-user-v1", "active leaf edge drift");
  check(spec.topology?.selectedLeafId === "tail-post-assistant-v1", "selected leaf drift");
  check(spec.continuation?.userMessage?.role === "user" && spec.continuation?.assistantMessage?.role === "assistant", "continuation shape drift");
  check(activeContextFromSpec(spec, false).messages.length === 5, "before context size drift");
  check(activeContextFromSpec(spec, true).messages.length === 7, "after context size drift");
  return spec;
}

export function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

export function allBooleansTrue(value) {
  let seen = 0;
  const visit = (item) => {
    if (typeof item === "boolean") {
      seen += 1;
      return item;
    }
    if (Array.isArray(item)) return item.every(visit);
    if (isObject(item)) return Object.values(item).every(visit);
    return true;
  };
  return visit(value) && seen > 0;
}

export function exactJsonEqual(left, right) {
  return stableStringify(left) === stableStringify(right);
}
