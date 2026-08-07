import assert from "node:assert/strict";
import {
	closeSync,
	ftruncateSync,
	mkdirSync,
	mkdtempSync,
	openSync,
	readFileSync,
	rmSync,
	writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const packageRoot = process.env.PI_BLACKHOLE_ROOT;
assert(packageRoot, "PI_BLACKHOLE_ROOT must name the packaged Blackhole root");
const requestedMessages = Number.parseInt(
	process.env.PI_BLACKHOLE_MESSAGES ?? "25000",
	10,
);
assert(Number.isSafeInteger(requestedMessages) && requestedMessages >= 5000);
const cleanupBodyBytes = Number.parseInt(
	process.env.PI_BLACKHOLE_CLEANUP_BODY_BYTES ?? "67108864",
	10,
);
const maxCleanupRssDeltaBytes = Number.parseInt(
	process.env.PI_BLACKHOLE_CLEANUP_MAX_RSS_DELTA_BYTES ?? "16777216",
	10,
);
assert(
	Number.isSafeInteger(cleanupBodyBytes) &&
		cleanupBodyBytes >= 32 * 1024 * 1024,
	"cleanup body must be at least 32 MiB",
);
assert(
	Number.isSafeInteger(maxCleanupRssDeltaBytes) &&
		maxCleanupRssDeltaBytes > 0 &&
		maxCleanupRssDeltaBytes < cleanupBodyBytes / 2,
	"cleanup RSS ceiling must be positive and less than half the body size",
);

for (const relative of [
	"src/core/lineage.ts",
	"src/om/compaction-trigger.ts",
	"src/om/consolidation.ts",
]) {
	const source = readFileSync(join(packageRoot, relative), "utf8");
	assert(
		!source.includes("sessionManager.getBranch()"),
		`${relative} must not hydrate the full branch`,
	);
}

const cleanupSource = readFileSync(
	join(packageRoot, "src/om/cleanup.ts"),
	"utf8",
);
const cleanupScanStart = cleanupSource.indexOf(
	"const MAX_SESSION_HEADER_BYTES",
);
const cleanupScanEnd = cleanupSource.indexOf(
	"/**\n * Read sessionDir override",
	cleanupScanStart,
);
assert(cleanupScanStart >= 0 && cleanupScanEnd > cleanupScanStart);
const cleanupScanSource = cleanupSource.slice(cleanupScanStart, cleanupScanEnd);
assert.match(cleanupScanSource, /MAX_SESSION_HEADER_BYTES = 64 \* 1024/);
assert.match(
	cleanupScanSource,
	/Buffer\.allocUnsafe\(MAX_SESSION_HEADER_BYTES \+ 1\)/,
);
for (const operation of [/\bopenSync\(/, /\breadSync\(/, /\bcloseSync\(/]) {
	assert.match(cleanupScanSource, operation);
}
assert.match(cleanupScanSource, /finally \{/);
assert(
	!cleanupScanSource.includes("readFileSync("),
	"cleanup session scan must not read a whole session file",
);

const { historyWindowNotice, loadAllMessages } = await import(
	join(packageRoot, "src/core/load-messages.ts")
);
const workdir = mkdtempSync(join(tmpdir(), "pi-blackhole-history-"));
const sessionFile = join(workdir, "session.jsonl");

function writeText(path: string, text: string): void {
	const fd = openSync(path, "w");
	try {
		writeSync(fd, text);
	} finally {
		closeSync(fd);
	}
}

function writeSession(path: string, id: string, bodyBytes = 0): void {
	const fd = openSync(path, "w");
	try {
		const header = `${JSON.stringify({ type: "session", version: 3, id })}\n`;
		writeSync(fd, header);
		if (bodyBytes > 0) {
			ftruncateSync(fd, Buffer.byteLength(header) + bodyBytes);
		}
	} finally {
		closeSync(fd);
	}
}

function classifications(report: {
	active: Array<{ sessionId: string }>;
	orphaned: Array<{ sessionId: string }>;
}): { active: string[]; orphaned: string[] } {
	return {
		active: report.active.map(({ sessionId }) => sessionId).sort(),
		orphaned: report.orphaned.map(({ sessionId }) => sessionId).sort(),
	};
}

try {
	const cleanupModuleRoot = join(workdir, "cleanup-module");
	const cleanupModuleDir = join(cleanupModuleRoot, "src/om");
	const cleanupModulePath = join(cleanupModuleDir, "cleanup.ts");
	const codingAgentStubDir = join(
		cleanupModuleRoot,
		"node_modules/@earendil-works/pi-coding-agent",
	);
	mkdirSync(cleanupModuleDir, { recursive: true });
	mkdirSync(codingAgentStubDir, { recursive: true });
	writeText(cleanupModulePath, cleanupSource);
	writeText(
		join(codingAgentStubDir, "package.json"),
		JSON.stringify({ type: "module", exports: "./index.js" }),
	);
	writeText(
		join(codingAgentStubDir, "index.js"),
		'export function getAgentDir() { throw new Error("getAgentDir must not be called by the focused check"); }\n',
	);
	const { analyzeOrphaned } = await import(cleanupModulePath);

	const cleanupRoot = join(workdir, "cleanup");
	const agentDir = join(cleanupRoot, "agent");
	const pendingDir = join(agentDir, "pi-blackhole");
	const smallSessionDir = join(cleanupRoot, "small-sessions");
	const largeSessionDir = join(cleanupRoot, "large-sessions");
	const malformedSessionDir = join(cleanupRoot, "malformed-sessions");
	const oversizedSessionDir = join(cleanupRoot, "oversized-sessions");
	for (const directory of [
		pendingDir,
		smallSessionDir,
		largeSessionDir,
		malformedSessionDir,
		oversizedSessionDir,
	]) {
		mkdirSync(directory, { recursive: true });
	}
	for (const id of [
		"active-session",
		"malformed-session",
		"missing-session",
		"oversized-session",
	]) {
		writeText(join(pendingDir, `${id}-pending.json`), "{}\n");
	}

	writeSession(join(smallSessionDir, "active.jsonl"), "active-session");
	writeSession(
		join(largeSessionDir, "active.jsonl"),
		"active-session",
		cleanupBodyBytes,
	);
	const smallReport = analyzeOrphaned(agentDir, [smallSessionDir]);
	assert.deepEqual(classifications(smallReport), {
		active: ["active-session"],
		orphaned: ["malformed-session", "missing-session", "oversized-session"],
	});
	const cleanupRssBefore = process.memoryUsage.rss();
	const largeReport = analyzeOrphaned(agentDir, [largeSessionDir]);
	const cleanupRssAfter = process.memoryUsage.rss();
	const cleanupRssDeltaBytes = Math.max(0, cleanupRssAfter - cleanupRssBefore);
	assert.deepEqual(
		classifications(largeReport),
		classifications(smallReport),
		"session body size must not affect cleanup classification",
	);
	assert(
		cleanupRssDeltaBytes <= maxCleanupRssDeltaBytes,
		`cleanup RSS grew by ${cleanupRssDeltaBytes} bytes while scanning a ${cleanupBodyBytes}-byte body`,
	);

	writeText(
		join(oversizedSessionDir, "oversized.jsonl"),
		`${JSON.stringify({
			type: "session",
			id: "oversized-session",
			padding: "x".repeat(128 * 1024),
		})}\n`,
	);
	let oversizedReport: ReturnType<typeof analyzeOrphaned> | undefined;
	assert.throws(() => {
		oversizedReport = analyzeOrphaned(agentDir, [oversizedSessionDir]);
	}, /session header exceeds 65536 bytes/);
	assert.equal(
		oversizedReport,
		undefined,
		"oversized header must not produce deletion candidates",
	);

	writeText(
		join(malformedSessionDir, "malformed.jsonl"),
		`{malformed}\n${JSON.stringify({ type: "session", id: "malformed-session" })}\n`,
	);
	let malformedReport: ReturnType<typeof analyzeOrphaned> | undefined;
	assert.throws(() => {
		malformedReport = analyzeOrphaned(agentDir, [malformedSessionDir]);
	}, /malformed session header/);
	assert.equal(
		malformedReport,
		undefined,
		"malformed header must not produce deletion candidates",
	);

	const fd = openSync(sessionFile, "w");
	try {
		writeSync(
			fd,
			`${JSON.stringify({ type: "session", version: 3, id: "session", timestamp: "t", cwd: workdir })}\n`,
		);
		let batch = "";
		for (let i = 0; i < requestedMessages; i++) {
			batch += `${JSON.stringify({
				type: "message",
				id: `entry-${i}`,
				parentId: i === 0 ? null : `entry-${i - 1}`,
				timestamp: `t-${i}`,
				message: { role: "user", content: `message-${i}`, timestamp: i },
			})}\n`;
			if (i % 1024 === 1023) {
				writeSync(fd, batch);
				batch = "";
			}
		}
		if (batch) writeSync(fd, batch);
	} finally {
		closeSync(fd);
	}

	const historyRssBefore = process.memoryUsage.rss();
	const loaded = loadAllMessages(sessionFile, false);
	const historyRssAfter = process.memoryUsage.rss();
	assert.equal(loaded.totalMessages, requestedMessages);
	assert.equal(loaded.rendered.length, 4096);
	assert.equal(loaded.rawMessages.length, 4096);
	assert.equal(loaded.entryIds.length, 4096);
	assert.equal(loaded.truncated, true);
	assert.equal(loaded.rendered[0]?.index, requestedMessages - 4096);
	assert.equal(loaded.rendered.at(-1)?.index, requestedMessages - 1);
	assert.match(
		historyWindowNotice(loaded),
		/bounded to 4,096 retained messages/,
	);

	console.log(
		JSON.stringify({
			cleanupBodyBytes,
			cleanupRssDeltaBytes,
			messages: requestedMessages,
			retainedMessages: loaded.rendered.length,
			historyRssDeltaBytes: historyRssAfter - historyRssBefore,
		}),
	);
} finally {
	rmSync(workdir, { recursive: true, force: true });
}
