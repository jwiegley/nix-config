import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
	closeSync,
	mkdirSync,
	mkdtempSync,
	openSync,
	readFileSync,
	readSync,
	rmSync,
	statSync,
	writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = process.env.PI_USAGE_ROOT;
assert(
	packageRoot,
	"PI_USAGE_ROOT must name the packaged Usage Dashboard root",
);

const dataPath = join(packageRoot, "data.ts");
const storePath = join(packageRoot, "bounded-store.ts");
const source = readFileSync(dataPath, "utf8");
const storeSource = readFileSync(storePath, "utf8");
assert.match(source, /new BoundedJsonlEntryParser\(\)/);
assert.match(source, /UsageCacheStore\.open\(cachePath\)/);
assert.match(source, /CREATE TEMP TABLE scan_seen_hashes/);
assert.match(storeSource, /PRAGMA temp_store = FILE/);
assert.match(storeSource, /CREATE TABLE IF NOT EXISTS messages/);
assert.match(storeSource, /getBuiltinModule\("bun:sqlite"\)/);
assert.match(storeSource, /getBuiltinModule\("node:sqlite"\)/);
assert.doesNotMatch(storeSource, /from "(?:bun|node):sqlite"/);
assert.doesNotMatch(source, /Buffer\.allocUnsafe\(probe\.length\)/);
assert.doesNotMatch(source, /readFile\(cachePath/);
assert.doesNotMatch(source, /const deduped: SessionMessage\[\]/);
const parseState = /interface SessionParseState \{([\s\S]*?)\n\}/.exec(source);
assert(parseState);
assert.doesNotMatch(parseState[1], /messages:|toolUsages:/);

const { collectUsageData, parseSessionBuffer, parseSessionFile } = await import(
	dataPath
);

interface CollectedRecords {
	messages: unknown[];
	toolUsages: unknown[];
}

function recordSink(records: CollectedRecords) {
	return {
		message(value: unknown): void {
			records.messages.push(value);
		},
		toolUsage(value: unknown): void {
			records.toolUsages.push(value);
		},
	};
}

function boundedHeader(path: string): string {
	const descriptor = openSync(path, "r");
	try {
		const header = Buffer.alloc(16);
		const bytesRead = readSync(descriptor, header, 0, header.length, 0);
		return header.subarray(0, bytesRead).toString("utf8");
	} finally {
		closeSync(descriptor);
	}
}

function rssLimit(): number {
	const value = Number.parseInt(
		process.env.PI_USAGE_RSS_LIMIT_BYTES ?? "100663296",
		10,
	);
	assert(Number.isSafeInteger(value) && value > 0);
	return value;
}

function summarizeStats(stats: {
	sessions: number;
	messages: number;
	cost: number;
	tokens: unknown;
	models?: Map<string, unknown>;
}): unknown {
	return {
		sessions: stats.sessions,
		messages: stats.messages,
		cost: stats.cost,
		tokens: stats.tokens,
		...(stats.models
			? {
					models: Object.fromEntries(
						[...stats.models.entries()]
							.sort(([left], [right]) => left.localeCompare(right))
							.map(([name, value]) => [
								name,
								summarizeStats(value as Parameters<typeof summarizeStats>[0]),
							]),
					),
				}
			: {}),
	};
}

const childMode = process.env.PI_USAGE_CHILD_MODE;
if (childMode === "giant") {
	const sessionFile = process.env.PI_USAGE_SESSION_FILE;
	assert(sessionFile);
	const records: CollectedRecords = { messages: [], toolUsages: [] };
	const rssBefore = process.memoryUsage.rss();
	const metadata = await parseSessionFile(
		sessionFile,
		undefined,
		recordSink(records),
	);
	const rssDeltaBytes = Math.max(0, process.memoryUsage.rss() - rssBefore);
	assert(
		rssDeltaBytes <= rssLimit(),
		`oversized record increased RSS by ${rssDeltaBytes} bytes`,
	);
	console.log(JSON.stringify({ metadata, records, rssDeltaBytes }));
	process.exit(0);
}

if (childMode === "scale") {
	const sessionsDir = process.env.PI_USAGE_SESSIONS_DIR;
	const cachePath = process.env.PI_USAGE_CACHE;
	const now = process.env.PI_USAGE_NOW;
	assert(sessionsDir && cachePath && now);
	let progress:
		| {
				mode: string;
				filesToParse: number;
				filesParsed: number;
		  }
		| undefined;
	const rssBefore = process.memoryUsage.rss();
	const data = await collectUsageData({
		sessionsDir,
		cachePath,
		now: new Date(now),
		onProgress(value: {
			mode: string;
			filesToParse: number;
			filesParsed: number;
		}): void {
			progress = value;
		},
	});
	assert(data);
	const rssDeltaBytes = Math.max(0, process.memoryUsage.rss() - rssBefore);
	assert(
		rssDeltaBytes <= rssLimit(),
		`relevant-history scan increased RSS by ${rssDeltaBytes} bytes`,
	);
	const providers = Object.fromEntries(
		[...data.allTime.providers.entries()]
			.sort(([left], [right]) => left.localeCompare(right))
			.map(([name, value]) => [name, summarizeStats(value)]),
	);
	const hourly = [...data.hourly.entries()].map(([hour, cells]) => [
		hour,
		[...cells.entries()],
	]);
	console.log(
		JSON.stringify({
			summary: {
				totals: data.allTime.totals,
				providers,
				hourly,
				insights: data.allTime.insights,
			},
			progress,
			rssDeltaBytes,
			cacheHeader: boundedHeader(cachePath),
			cacheMode: statSync(cachePath).mode & 0o777,
			cacheBytes: statSync(cachePath).size,
		}),
	);
	process.exit(0);
}

function spawnChild(env: Record<string, string>): Record<string, unknown> {
	const child = spawnSync(process.execPath, [fileURLToPath(import.meta.url)], {
		encoding: "utf8",
		env: { ...process.env, ...env },
		maxBuffer: 1024 * 1024,
	});
	assert.equal(child.status, 0, child.stderr || child.stdout);
	return JSON.parse(child.stdout.trim().split("\n").at(-1) ?? "{}");
}

function usage(cost = 1) {
	return {
		cost: { total: cost },
		input: 1,
		output: 1,
		cacheRead: 1,
		cacheWrite: 1,
		reasoning: 0,
	};
}

function assistantEntry(timestamp: number) {
	return {
		type: "message",
		id: "assistant",
		timestamp,
		message: {
			role: "assistant",
			provider: "provider",
			model: "model",
			timestamp,
			usage: usage(1.25),
		},
	};
}

function toolEntry(timestamp: number) {
	return {
		type: "message",
		id: "tool",
		timestamp,
		message: {
			role: "toolResult",
			toolName: "subagent",
			timestamp,
			usage: usage(0.4),
			details: {
				runId: "run",
				results: [{ sessionFile: "child.jsonl", usage: usage(0.2) }],
			},
		},
	};
}

async function compactRecords(
	sessionId: string,
	cwd: string,
	entry: unknown,
): Promise<{ metadata: unknown; records: CollectedRecords }> {
	const records: CollectedRecords = { messages: [], toolUsages: [] };
	const buffer = Buffer.from(
		[
			JSON.stringify({ type: "session", id: sessionId, cwd }),
			JSON.stringify(entry),
		].join("\n"),
	);
	const metadata = await parseSessionBuffer(
		buffer,
		undefined,
		recordSink(records),
	);
	return { metadata, records };
}

function writeGiantRecord(
	path: string,
	sessionId: string,
	prefix: string,
	suffix: string,
	payloadBytes: number,
): void {
	const descriptor = openSync(path, "w");
	try {
		writeSync(
			descriptor,
			`${JSON.stringify({ type: "session", id: sessionId, cwd: dirname(path) })}\n`,
		);
		writeSync(descriptor, prefix);
		const block = Buffer.alloc(64 * 1024, 0x78);
		for (
			let remaining = payloadBytes;
			remaining > 0;
			remaining -= block.length
		) {
			writeSync(descriptor, block, 0, Math.min(remaining, block.length));
		}
		writeSync(descriptor, suffix);
	} finally {
		closeSync(descriptor);
	}
}

function writeScaleHistory(
	path: string,
	recordCount: number,
	baseTimestamp: number,
): void {
	const descriptor = openSync(path, "w");
	try {
		writeSync(
			descriptor,
			`${JSON.stringify({ type: "session", id: "scale", cwd: "/Users/test/project" })}\n`,
		);
		for (let index = 0; index < recordCount; index++) {
			const timestamp = baseTimestamp + index;
			let entry: unknown;
			if (index % 3 === 0) {
				entry = {
					type: "message",
					id: `assistant-${index}`,
					timestamp,
					message: {
						role: "assistant",
						provider: "provider",
						model: "model",
						timestamp,
						usage: usage(),
					},
				};
			} else if (index % 3 === 1) {
				entry = {
					type: "branch_summary",
					id: `summary-${index}`,
					timestamp,
					usage: usage(),
				};
			} else {
				entry = {
					type: "message",
					id: `tool-${index}`,
					timestamp,
					message: {
						role: "toolResult",
						toolName: "shell",
						timestamp,
						usage: usage(),
					},
				};
			}
			writeSync(descriptor, `${JSON.stringify(entry)}\n`);
		}
	} finally {
		closeSync(descriptor);
	}
}

const workdir = mkdtempSync(join(tmpdir(), "pi-usage-bounded-"));
try {
	const payloadBytes = Number.parseInt(
		process.env.PI_USAGE_TEST_PAYLOAD_BYTES ?? "67108864",
		10,
	);
	assert(
		Number.isSafeInteger(payloadBytes) && payloadBytes >= 16 * 1024 * 1024,
	);

	const assistantPath = join(workdir, "giant-assistant.jsonl");
	writeGiantRecord(
		assistantPath,
		"giant-assistant",
		'{"type":"message","id":"assistant","message":{"role":"assistant","content":"',
		'","provider":"provider","model":"model","timestamp":11,"usage":{"cost":{"total":1.25},"input":1,"output":1,"cacheRead":1,"cacheWrite":1,"reasoning":0}}}',
		payloadBytes,
	);
	const assistantExpected = await compactRecords(
		"giant-assistant",
		workdir,
		assistantEntry(11),
	);
	const assistantReport = spawnChild({
		PI_USAGE_CHILD_MODE: "giant",
		PI_USAGE_SESSION_FILE: assistantPath,
	});
	assert.deepEqual(
		{
			metadata: assistantReport.metadata,
			records: assistantReport.records,
		},
		assistantExpected,
	);

	const toolPath = join(workdir, "giant-tool.jsonl");
	writeGiantRecord(
		toolPath,
		"giant-tool",
		'{"type":"message","id":"tool","message":{"role":"toolResult","toolName":"subagent","content":"',
		'","details":{"runId":"run","results":[{"sessionFile":"child.jsonl","usage":{"cost":{"total":0.2},"input":1,"output":1,"cacheRead":1,"cacheWrite":1,"reasoning":0}}]},"timestamp":12,"usage":{"cost":{"total":0.4},"input":1,"output":1,"cacheRead":1,"cacheWrite":1,"reasoning":0}}}',
		payloadBytes,
	);
	const toolExpected = await compactRecords(
		"giant-tool",
		workdir,
		toolEntry(12),
	);
	const toolReport = spawnChild({
		PI_USAGE_CHILD_MODE: "giant",
		PI_USAGE_SESSION_FILE: toolPath,
	});
	assert.deepEqual(
		{ metadata: toolReport.metadata, records: toolReport.records },
		toolExpected,
	);

	const falsePositivePath = join(workdir, "giant-false-positive.jsonl");
	const quotedUsage = JSON.stringify(
		'"usage":{"cost":{"total":9},"input":9}',
	).slice(1, -1);
	writeGiantRecord(
		falsePositivePath,
		"giant-false-positive",
		'{"type":"message","id":"false","message":{"role":"toolResult","toolName":"read","content":"',
		`${quotedUsage}"}}`,
		payloadBytes,
	);
	const falseExpected = await compactRecords("giant-false-positive", workdir, {
		type: "message",
		id: "false",
		message: {
			role: "toolResult",
			toolName: "read",
			content: '"usage":{"cost":{"total":9},"input":9}',
		},
	});
	const falseReport = spawnChild({
		PI_USAGE_CHILD_MODE: "giant",
		PI_USAGE_SESSION_FILE: falsePositivePath,
	});
	assert.deepEqual(
		{ metadata: falseReport.metadata, records: falseReport.records },
		falseExpected,
	);

	const aborted = new AbortController();
	aborted.abort();
	assert.deepEqual(await parseSessionFile(assistantPath, aborted.signal), {
		sessionId: "",
		cwd: "",
		messageCount: 0,
		toolUsageCount: 0,
	});

	const scaleCount = Number.parseInt(
		process.env.PI_USAGE_RELEVANT_RECORDS ?? "250000",
		10,
	);
	assert(Number.isSafeInteger(scaleCount) && scaleCount >= 50_000);
	const sessionsDir = join(workdir, "sessions");
	mkdirSync(sessionsDir);
	const baseTimestamp = Date.UTC(2026, 7, 6, 12, 0, 0);
	writeScaleHistory(
		join(sessionsDir, "scale.jsonl"),
		scaleCount,
		baseTimestamp,
	);
	const cachePath = join(workdir, "usage-cache.json");
	const scaleEnv = {
		PI_USAGE_CHILD_MODE: "scale",
		PI_USAGE_SESSIONS_DIR: sessionsDir,
		PI_USAGE_CACHE: cachePath,
		PI_USAGE_NOW: new Date(baseTimestamp + 30 * 60_000).toISOString(),
	};
	const cold = spawnChild(scaleEnv);
	const warm = spawnChild(scaleEnv);
	assert.deepEqual(cold.summary, warm.summary);
	assert.equal((cold.progress as { filesToParse: number }).filesToParse, 1);
	assert.equal((warm.progress as { filesToParse: number }).filesToParse, 0);
	assert.equal(cold.cacheHeader, "SQLite format 3\0");
	assert.equal(warm.cacheHeader, "SQLite format 3\0");
	assert.equal(cold.cacheMode, 0o600);
	assert.equal(warm.cacheMode, 0o600);

	const assistantCount = Math.floor((scaleCount + 2) / 3);
	const totals = (
		cold.summary as {
			totals: {
				sessions: number;
				messages: number;
				cost: number;
				tokens: {
					total: number;
					input: number;
					output: number;
					cacheRead: number;
					cacheWrite: number;
				};
			};
			hourly: unknown[];
		}
	).totals;
	assert.deepEqual(totals, {
		sessions: 1,
		messages: assistantCount,
		cost: scaleCount,
		tokens: {
			total: scaleCount * 3,
			input: scaleCount,
			output: scaleCount,
			cacheRead: scaleCount,
			cacheWrite: scaleCount,
		},
	});
	assert.equal((cold.summary as { hourly: unknown[] }).hourly.length, 1);
	console.log(
		JSON.stringify({
			payloadBytes,
			giantRssBytes: {
				assistant: assistantReport.rssDeltaBytes,
				tool: toolReport.rssDeltaBytes,
				falsePositive: falseReport.rssDeltaBytes,
			},
			relevantRecords: scaleCount,
			coldRssDeltaBytes: cold.rssDeltaBytes,
			warmRssDeltaBytes: warm.rssDeltaBytes,
			cacheBytes: warm.cacheBytes,
		}),
	);
} finally {
	rmSync(workdir, { recursive: true, force: true });
}
