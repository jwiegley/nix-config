import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import {
	copyFileSync,
	closeSync,
	createReadStream,
	mkdtempSync,
	openSync,
	readSync,
	rmSync,
	statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath, pathToFileURL } from "node:url";

const MiB = 1024 * 1024;
const mode = process.argv[2];
const sessionPath = process.argv[3];
const scriptPath = fileURLToPath(import.meta.url);
const packageRoot = process.env.PI_CODING_AGENT_ROOT;

const report = (value) => console.log(JSON.stringify(value));
const settle = () => new Promise((resolve) => setTimeout(resolve, 50));
const maxRss = () => process.resourceUsage().maxRSS * 1024;
const sha256File = async (path) => {
	const hash = createHash("sha256");
	for await (const chunk of createReadStream(path)) hash.update(chunk);
	return hash.digest("hex");
};
const loadManager = async () => {
	if (!packageRoot) throw new Error("PI_CODING_AGENT_ROOT is required");
	return (
		await import(
			pathToFileURL(join(packageRoot, "dist/core/session-manager.js")).href
		)
	).SessionManager;
};

async function reference(path) {
	const hash = createHash("sha256");
	const lines = createInterface({
		input: createReadStream(path),
		crlfDelay: Infinity,
	});
	let entries = 0;
	let messages = 0;
	let header;
	let parentId = null;
	let firstId;
	let linearMessages = true;
	let byteOffset = 0;
	const messageLocations = [];
	for await (const line of lines) {
		const lineBytes = Buffer.byteLength(line);
		const lineOffset = byteOffset;
		byteOffset += lineBytes + 1;
		if (!line) continue;
		const entry = JSON.parse(line);
		if (entry.type === "session") {
			header ??= entry;
			continue;
		}
		entries++;
		firstId ??= entry.id;
		linearMessages &&= entry.type === "message" && entry.parentId === parentId;
		parentId = entry.id;
		if (entry.type !== "message") continue;
		hash.update(JSON.stringify(entry.message));
		hash.update("\n");
		messageLocations.push([lineOffset, lineBytes]);
		messages++;
	}
	const reverseHash = createHash("sha256");
	const fd = openSync(path, "r");
	try {
		for (let index = messageLocations.length - 1; index >= 0; index--) {
			const [offset, length] = messageLocations[index];
			const bytes = Buffer.allocUnsafe(length);
			let read = 0;
			while (read < length) {
				const count = readSync(fd, bytes, read, length - read, offset + read);
				assert(count > 0, "short reverse-reference read");
				read += count;
			}
			reverseHash.update(JSON.stringify(JSON.parse(bytes.toString("utf8")).message));
			reverseHash.update("\n");
		}
	} finally {
		closeSync(fd);
	}
	return {
		entries,
		messages,
		hash: hash.digest("hex"),
		reverseHash: reverseHash.digest("hex"),
		sessionId: header?.id,
		firstId,
		leafId: parentId,
		linearMessages,
	};
}

async function childResult(childMode, path = "") {
	const child = spawnSync(process.execPath, [scriptPath, childMode, path], {
		env: process.env,
		encoding: "utf8",
		maxBuffer: 10 * MiB,
	});
	assert.equal(child.status, 0, child.stderr || child.stdout);
	return JSON.parse(child.stdout.trim().split("\n").at(-1));
}

async function fixture(path) {
	assert(path, "fixture mode requires a JSONL path");
	const sourceHash = await sha256File(path);
	const root = mkdtempSync(join(tmpdir(), "pi-session-fixture-"));
	const copy = join(root, "session.jsonl");
	copyFileSync(path, copy);
	try {
		const baseline = await childResult("_baseline");
		const expected = await childResult("_reference", path);
		assert(
			expected.linearMessages,
			"fixture must be a linear all-message session for normalized comparison",
		);
		const cold = await childResult("_open", copy);
		const context = await childResult("_context", copy);
		const reverse = await childResult("_reverse", copy);
		const lineage = await childResult("_lineage", copy);
		const all = await childResult("_all", copy);
		const tree = await childResult("_tree", copy);
		assert.equal(cold.sessionId, expected.sessionId);
		assert.equal(cold.leafId, expected.leafId);
		assert.equal(cold.contextMessages, expected.messages);
		assert.equal(context.hash, expected.hash);
		assert.equal(reverse.hash, expected.reverseHash);
		assert.equal(all.hash, expected.hash);
		assert.equal(lineage.hash, expected.reverseHash);
		assert.equal(context.messages, expected.messages);
		assert.equal(reverse.messages, expected.messages);
		assert.equal(lineage.messages, expected.messages);
		assert.equal(lineage.firstId, expected.leafId);
		assert.equal(lineage.lastId, expected.firstId);
		assert.equal(all.messages, expected.messages);
		assert.deepEqual(
			{
				roots: tree.roots,
				entries: tree.entries,
				firstId: tree.firstId,
				leafId: tree.leafId,
			},
			{
				roots: 1,
				entries: expected.entries,
				firstId: expected.firstId,
				leafId: expected.leafId,
			},
		);
		assert.equal(await sha256File(path), sourceHash, "source fixture changed");
		assert.equal(
			await sha256File(copy),
			sourceHash,
			"fixture copy JSONL changed",
		);
		assert(
			cold.maxRss <= baseline.maxRss + 256 * MiB,
			`cold startup ${cold.maxRss} exceeded limit ${baseline.maxRss + 256 * MiB}`,
		);
		assert(cold.maxRss < 1024 * MiB, "cold startup exceeded 1 GiB");
		assert(
			cold.steadyRss <= baseline.steadyRss + 128 * MiB,
			`loaded steady RSS ${cold.steadyRss} exceeded limit ${baseline.steadyRss + 128 * MiB}`,
		);
		assert(
			lineage.maxRss <= cold.steadyRss + 128 * MiB,
			`lineage recall ${lineage.maxRss} exceeded limit ${cold.steadyRss + 128 * MiB}`,
		);
		assert(
			reverse.maxRss <= cold.steadyRss + 128 * MiB,
			`reverse context ${reverse.maxRss} exceeded limit ${cold.steadyRss + 128 * MiB}`,
		);
		assert(
			context.maxRss <= cold.steadyRss + 256 * MiB,
			`context equivalence ${context.maxRss} exceeded limit ${cold.steadyRss + 256 * MiB}`,
		);
		assert(
			all.maxRss <= cold.steadyRss + 256 * MiB,
			`all-history recall ${all.maxRss} exceeded limit ${cold.steadyRss + 256 * MiB}`,
		);
		assert(
			tree.maxRss <= cold.steadyRss + 256 * MiB,
			"tree navigation exceeded steady + 256 MiB",
		);
		report({
			mode: "fixture",
			source: { bytes: statSync(path).size, sha256: sourceHash },
			baseline,
			expected,
			cold,
			context,
			reverse,
			lineage,
			all,
			tree,
		});
	} finally {
		if (process.env.PI_SESSION_KEEP !== "1")
			rmSync(root, { recursive: true, force: true });
	}
}

async function baselineChild() {
	const SessionManager = await loadManager();
	const root = mkdtempSync(join(tmpdir(), "pi-session-baseline-"));
	try {
		const manager = SessionManager.create(root, root, {
			id: `baseline-${randomUUID()}`,
		});
		manager.appendMessage({ role: "user", content: "baseline", timestamp: 1 });
		manager.buildSessionContext();
		await settle();
		const result = {
			steadyRss: process.memoryUsage().rss,
			maxRss: maxRss(),
			process: process.memoryUsage(),
		};
		manager.close();
		report(result);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

async function openChild(path) {
	const SessionManager = await loadManager();
	const manager = SessionManager.open(path);
	const context = manager.buildSessionContextSource();
	const newest = context.messages.iterateReverse()[Symbol.iterator]().next().value;
	await settle();
	report({
		sessionId: manager.getSessionId(),
		leafId: manager.getLeafId(),
		contextMessages: context.messages.length,
		lastRole: context.messages.last()?.role,
		newestRole: newest?.role,
		thinkingLevel: context.thinkingLevel,
		model: context.model,
		steadyRss: process.memoryUsage().rss,
		maxRss: maxRss(),
		process: process.memoryUsage(),
		metrics: manager.getHistoryMetrics(),
	});
	manager.close();
}

async function reverseContextChild(path) {
	const SessionManager = await loadManager();
	const manager = SessionManager.open(path);
	const source = manager.buildSessionContextSource().messages;
	const hash = createHash("sha256");
	let messages = 0;
	for (const message of source.iterateReverse()) {
		hash.update(JSON.stringify(message));
		hash.update("\n");
		messages++;
	}
	assert.equal(messages, source.length);
	await settle();
	report({
		messages,
		hash: hash.digest("hex"),
		steadyRss: process.memoryUsage().rss,
		maxRss: maxRss(),
		process: process.memoryUsage(),
		metrics: manager.getHistoryMetrics(),
	});
	manager.close();
}

async function recallChild(path, allHistory) {
	const SessionManager = await loadManager();
	const manager = SessionManager.open(path);
	const hash = createHash("sha256");
	let messages = 0;
	const visit = (message) => {
		hash.update(JSON.stringify(message));
		hash.update("\n");
		messages++;
	};
	if (allHistory) {
		await manager.iterateEntries({ type: "message" }, (entry) =>
			visit(entry.message),
		);
	} else {
		for (const message of manager.buildSessionContext().messages)
			visit(message);
	}
	await settle();
	report({
		messages,
		hash: hash.digest("hex"),
		steadyRss: process.memoryUsage().rss,
		maxRss: maxRss(),
		process: process.memoryUsage(),
	});
	manager.close();
}

async function lineageChild(path) {
	const SessionManager = await loadManager();
	const manager = SessionManager.open(path);
	const hash = createHash("sha256");
	let messages = 0;
	let firstId;
	let lastId;
	let expectedId = manager.getLeafId();
	await manager.iterateActiveAncestry((metadata) => {
		assert.equal(metadata.id, expectedId, "active ancestry is not a contiguous leaf-to-root chain");
		firstId ??= metadata.id;
		lastId = metadata.id;
		expectedId = metadata.parentId;
		if (metadata.type !== "message") return;
		const entry = manager.getEntry(metadata.id);
		if (entry?.type !== "message") return;
		hash.update(JSON.stringify(entry.message));
		hash.update("\n");
		messages++;
	});
	await settle();
	report({
		messages,
		hash: hash.digest("hex"),
		firstId,
		lastId,
		steadyRss: process.memoryUsage().rss,
		maxRss: maxRss(),
		process: process.memoryUsage(),
	});
	manager.close();
}

async function treeChild(path) {
	const SessionManager = await loadManager();
	const manager = SessionManager.open(path);
	const pageLimit = 4096;
	let afterOrdinal;
	let entries = 0;
	let roots = 0;
	let firstId;
	let leafId;
	let previousId = null;
	let maxPreviewBytes = 0;
	while (true) {
		const cacheBytes = manager.getHistoryMetrics().session_hydration_cache_bytes;
		const page = await manager.getTreePage({
			afterOrdinal,
			direction: "forward",
			limit: pageLimit,
		});
		for (const record of page.entries) {
			assert.equal(record.ordinal, entries);
			assert.equal(record.messageOrdinal, entries);
			assert.equal(record.type, "message");
			assert.equal(record.parentId, previousId);
			assert.equal(manager.getEntryMetadata(record.id)?.ordinal, record.ordinal);
			assert(record.entryPreview, "tree page omitted its bounded entry preview");
			assert.equal(record.entryPreview.id, record.id);
			assert.equal(record.entryPreview.type, "message");
			const previewContent = record.entryPreview.message.content;
			assert.equal(typeof previewContent, "string");
			const previewBytes = Buffer.byteLength(previewContent);
			assert(previewBytes <= 3072, `tree preview exceeded 3072 bytes: ${previewBytes}`);
			maxPreviewBytes = Math.max(maxPreviewBytes, previewBytes);
			if (record.parentId === null || record.parentId === record.id) roots++;
			entries++;
			firstId ??= record.id;
			leafId = record.id;
			previousId = record.id;
		}
		assert.equal(
			manager.getHistoryMetrics().session_hydration_cache_bytes,
			cacheBytes,
			"tree metadata page hydrated full session records",
		);
		if (page.nextOrdinal === null) break;
		assert(page.entries.length > 0, "tree page cursor advanced without entries");
		assert.equal(page.nextOrdinal, page.entries.at(-1).ordinal);
		assert.notEqual(page.nextOrdinal, afterOrdinal, "tree page cursor did not advance");
		afterOrdinal = page.nextOrdinal;
	}
	assert.equal(leafId, manager.getLeafId());
	assert.equal(manager.getEntry(leafId)?.id, leafId, "selected tree entry did not hydrate on demand");
	await settle();
	report({
		roots,
		entries,
		firstId,
		leafId,
		maxPreviewBytes,
		steadyRss: process.memoryUsage().rss,
		maxRss: maxRss(),
		process: process.memoryUsage(),
	});
	manager.close();
}

const median = (values) => {
	const sorted = [...values].sort((left, right) => left - right);
	return sorted[Math.floor(sorted.length / 2)];
};

async function growth(workload) {
	const SessionManager = await loadManager();
	const root = mkdtempSync(join(tmpdir(), `pi-session-${workload}-`));
	const targetBytes = Number(process.env.PI_SESSION_SCALE_BYTES ?? 1024 * MiB);
	const durationMs = Number(
		process.env.PI_SESSION_SOAK_MS ?? 8 * 60 * 60 * 1000,
	);
	const payloadBytes = Number(
		process.env.PI_SESSION_PAYLOAD_BYTES ??
			(workload === "scale" ? MiB : 32 * 1024),
	);
	const compactionEvery = Number(process.env.PI_SESSION_COMPACTION_EVERY ?? 16);
	const intervalMs =
		workload === "soak"
			? Number(process.env.PI_SESSION_INTERVAL_MS ?? 1000)
			: 0;
	const minimumCompactions = Number(
		process.env.PI_SESSION_MIN_COMPACTIONS ?? 4,
	);
	const checkpointEvery = Number(process.env.PI_SESSION_CHECKPOINT_EVERY ?? 60);
	const payload = "x".repeat(payloadBytes);
	const created = SessionManager.create(root, root, {
		id: `${workload}-${randomUUID()}`,
	});
	created.appendMessage({
		role: "user",
		content: "synthetic history",
		timestamp: 0,
	});
	created.appendMessage({
		role: "assistant",
		content: [{ type: "text", text: "starting synthetic history" }],
		api: "anthropic-messages",
		provider: "fixture",
		model: "fixture",
		usage: {
			input: 1,
			output: 1,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 2,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason: "stop",
		timestamp: 0,
	});
	const createdPath = created.getSessionFile();
	created.close();
	assert(createdPath, "synthetic session was not persisted");
	const manager = SessionManager.open(createdPath);
	const samples = [];
	const started = Date.now();
	let messages = 0;
	let lastId;
	try {
		while (
			workload === "scale"
				? (manager.getHistoryMetrics()?.session_history_bytes ?? 0) <
					targetBytes
				: Date.now() - started < durationMs
		) {
			lastId = manager.appendMessage({
				role: "toolResult",
				toolCallId: `call-${messages}`,
				toolName: "memory-soak",
				content: [{ type: "text", text: payload }],
				isError: false,
				timestamp: messages,
			});
			messages++;
			if (messages % compactionEvery === 0) {
				manager.appendCompaction(
					"bounded synthetic summary",
					lastId,
					payloadBytes * compactionEvery,
				);
				const metrics = manager.getHistoryMetrics();
				const rss = process.memoryUsage().rss;
				samples.push({
					historyBytes: metrics.session_history_bytes,
					rss,
					adjustedRss:
						rss -
						metrics.session_active_payload_bytes -
						metrics.session_hydration_cache_bytes,
				});
				if (samples.length === 1 || samples.length % checkpointEvery === 0) {
					report({
						mode: `${workload}-checkpoint`,
						durationMs: Date.now() - started,
						messages,
						compactions: samples.length,
						...samples.at(-1),
					});
				}
			}
			if (intervalMs)
				await new Promise((resolve) => setTimeout(resolve, intervalMs));
		}
		if (messages % compactionEvery !== 0 && lastId) {
			manager.appendCompaction(
				"bounded synthetic summary",
				lastId,
				payloadBytes * (messages % compactionEvery),
			);
			const metrics = manager.getHistoryMetrics();
			const rss = process.memoryUsage().rss;
			samples.push({
				historyBytes: metrics.session_history_bytes,
				rss,
				adjustedRss:
					rss -
					metrics.session_active_payload_bytes -
					metrics.session_hydration_cache_bytes,
			});
		}
		assert(
			samples.length >= minimumCompactions,
			`only ${samples.length} compactions completed`,
		);
		const quarter = Math.max(1, Math.floor(samples.length / 4));
		const first = median(
			samples.slice(0, quarter).map((sample) => sample.adjustedRss),
		);
		const last = median(
			samples.slice(-quarter).map((sample) => sample.adjustedRss),
		);
		const adjustedGrowth = last - first;
		const metrics = manager.getHistoryMetrics();
		if (workload === "scale")
			assert(
				metrics.session_history_bytes >= targetBytes,
				"synthetic history missed target",
			);
		assert(
			adjustedGrowth < 128 * MiB,
			`adjusted steady RSS grew by ${adjustedGrowth} bytes`,
		);
		report({
			mode: workload,
			durationMs: Date.now() - started,
			messages,
			compactions: samples.length,
			payloadBytes,
			adjustedGrowth,
			firstQuarterMedian: first,
			lastQuarterMedian: last,
			maxRss: maxRss(),
			process: process.memoryUsage(),
			metrics,
			retainedPath:
				process.env.PI_SESSION_KEEP === "1"
					? manager.getSessionFile()
					: undefined,
		});
	} finally {
		manager.close();
		if (process.env.PI_SESSION_KEEP !== "1")
			rmSync(root, { recursive: true, force: true });
	}
}

if (mode === "fixture") await fixture(sessionPath);
else if (mode === "scale" || mode === "soak") await growth(mode);
else if (mode === "_baseline") await baselineChild();
else if (mode === "_reference") report(await reference(sessionPath));
else if (mode === "_open") await openChild(sessionPath);
else if (mode === "_context") await recallChild(sessionPath, false);
else if (mode === "_reverse") await reverseContextChild(sessionPath);
else if (mode === "_lineage") await lineageChild(sessionPath);
else if (mode === "_all") await recallChild(sessionPath, true);
else if (mode === "_tree") await treeChild(sessionPath);
else
	throw new Error(
		"usage: pi-session-memory.check.mjs fixture SESSION | scale | soak",
	);
