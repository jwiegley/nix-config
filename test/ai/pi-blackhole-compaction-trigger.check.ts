import assert from "node:assert/strict";
import {
	chmodSync,
	cpSync,
	lstatSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	readdirSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const packageRoot = process.env.PI_BLACKHOLE_ROOT;
assert(packageRoot, "PI_BLACKHOLE_ROOT must name the packaged Blackhole root");
const packageVersion = JSON.parse(
	readFileSync(join(packageRoot, "package.json"), "utf8"),
).version;
assert.match(packageVersion, /^0\.4\.[78]$/, "unexpected Blackhole version");

function makeTreeWritable(root: string): void {
	const metadata = lstatSync(root);
	if (metadata.isSymbolicLink()) return;
	if (!metadata.isDirectory()) {
		chmodSync(root, 0o600);
		return;
	}
	chmodSync(root, 0o700);
	for (const child of readdirSync(root)) {
		makeTreeWritable(join(root, child));
	}
}

const workdir = mkdtempSync(join(tmpdir(), "pi-blackhole-trigger-"));
try {
	const moduleRoot = join(workdir, "pi-blackhole");
	mkdirSync(moduleRoot);
	cpSync(join(packageRoot, "src"), join(moduleRoot, "src"), {
		recursive: true,
	});
	writeFileSync(
		join(moduleRoot, "package.json"),
		JSON.stringify({ type: "module" }),
	);

	const agentStub = join(
		moduleRoot,
		"node_modules/@earendil-works/pi-coding-agent",
	);
	mkdirSync(agentStub, { recursive: true });
	writeFileSync(
		join(agentStub, "package.json"),
		JSON.stringify({ type: "module", exports: "./index.js" }),
	);
	writeFileSync(
		join(agentStub, "index.js"),
		[
			"export class AgentSession {}",
			"export function calculateContextTokens() { return 0; }",
			"export function estimateTokens() { return 0; }",
			`export function getAgentDir() { return ${JSON.stringify(workdir)}; }`,
		].join("\n"),
	);
	const typeboxStub = join(moduleRoot, "node_modules/typebox");
	mkdirSync(typeboxStub, { recursive: true });
	writeFileSync(
		join(typeboxStub, "package.json"),
		JSON.stringify({ type: "module", exports: "./index.js" }),
	);
	writeFileSync(
		join(typeboxStub, "index.js"),
		[
			"const shape = () => ({});",
			"export const Type = { Array: shape, Number: shape, Object: shape, Optional: shape, String: shape };",
		].join("\n"),
	);
	const piAiStub = join(
		moduleRoot,
		"node_modules/@earendil-works/pi-ai",
	);
	mkdirSync(piAiStub, { recursive: true });
	writeFileSync(
		join(piAiStub, "package.json"),
		JSON.stringify({ type: "module", exports: "./index.js" }),
	);
	writeFileSync(
		join(piAiStub, "index.js"),
		"export function StringEnum() { return {}; }\n",
	);

	const { registerCompactionTrigger } = await import(
		join(moduleRoot, "src/om/compaction-trigger.ts")
	);
	const handlers = new Map<string, (...args: any[]) => unknown>();
	const pi = {
		on(event: string, handler: (...args: any[]) => unknown): void {
			handlers.set(event, handler);
		},
	};
	const runtime: any = {
		autoCompactionController: null,
		compactInFlight: false,
		config: {
			compactAfterTokens: 81_000,
			compaction: "auto",
			compactionEngine: "blackhole",
			debugLog: false,
			midRunCompaction: "resume",
		},
		ensureConfig(): void {},
		midRunCompactionRetry: { failures: 0, retryAfter: 0 },
		midRunCompactionSuspended: false,
		resetInfoGate(): void {},
		tryEmitInfo(): boolean {
			return false;
		},
	};

	let inlineCalls = 0;
	let inlineShouldFail = false;
	let nativeCalls = 0;
	let historyMaterializations = 0;
	const sessionManager = {
		getActiveContextEntries(): never {
			historyMaterializations += 1;
			throw new Error("live context pressure must not hydrate history");
		},
	};
	registerCompactionTrigger(pi as any, runtime, async (actual: object) => {
		inlineCalls += 1;
		assert.equal(actual, sessionManager);
		if (inlineShouldFail) throw new Error("fixture inline failure");
		return {} as any;
	});

	const turnEnd = handlers.get("turn_end");
	assert(turnEnd, "Blackhole must register a turn_end compaction trigger");
	let contextTokens = 70;
	const ctx = {
		compact(): void {
			nativeCalls += 1;
		},
		cwd: workdir,
		getContextUsage: () => ({ contextWindow: 100, tokens: contextTokens }),
		hasUI: false,
		sessionManager,
		signal: new AbortController().signal,
	};

	await turnEnd({}, ctx);
	assert.equal(inlineCalls, 1, "resume mode must use the injected inline compactor");
	assert.equal(nativeCalls, 0, "resume mode must not invoke native pausing compaction");
	assert.equal(historyMaterializations, 0);
	assert.equal(runtime.compactInFlight, false);
	if (packageVersion === "0.4.7") {
		assert.equal(runtime.midRunCompactionSuspended, false);
	} else {
		assert.deepEqual(runtime.midRunCompactionRetry, {
			failures: 0,
			retryAfter: 0,
		});
	}

	inlineShouldFail = true;
	await turnEnd({}, ctx);
	assert.equal(inlineCalls, 2);
	assert.equal(runtime.compactInFlight, false);
	if (packageVersion === "0.4.7") {
		assert.equal(runtime.midRunCompactionSuspended, true);
	} else {
		assert.equal(runtime.midRunCompactionRetry.failures, 1);
		assert(runtime.midRunCompactionRetry.retryAfter > Date.now());
		runtime.midRunCompactionRetry.retryAfter = Date.now() + 60_000;
	}

	await turnEnd({}, ctx);
	assert.equal(inlineCalls, 2, "failure state must suppress an immediate retry");

	contextTokens = 69;
	await turnEnd({}, ctx);
	assert.equal(inlineCalls, 2, "pressure relief must not retry inline compaction");
	if (packageVersion === "0.4.7") {
		assert.equal(runtime.midRunCompactionSuspended, false);
	} else {
		assert.deepEqual(runtime.midRunCompactionRetry, {
			failures: 0,
			retryAfter: 0,
		});
	}
	assert.equal(nativeCalls, 0);
	assert.equal(historyMaterializations, 0);

	const { registerRecallTool } = await import(
		join(moduleRoot, "src/tools/recall.ts")
	);
	const activeEntry = {
		type: "message",
		id: "active",
		message: { role: "user", content: "active payload", timestamp: 1 },
	};
	const abandonedEntry = {
		type: "message",
		id: "abandoned",
		message: { role: "user", content: "abandoned payload", timestamp: 2 },
	};
	const metadata = new Map([
		["active", { id: "active", messageOrdinal: 0, ordinal: 0, type: "message" }],
		["abandoned", { id: "abandoned", messageOrdinal: 1, ordinal: 1, type: "message" }],
	]);
	const entries = new Map([
		["active", activeEntry],
		["abandoned", abandonedEntry],
	]);
	const recallSessionManager = {
		getEntry: (id: string) => entries.get(id),
		getEntryMetadata: (id: string) => metadata.get(id),
		getMessageByOrdinal: (ordinal: number) =>
			ordinal === 0 ? activeEntry : ordinal === 1 ? abandonedEntry : undefined,
		getSessionFile: () => "fixture.jsonl",
		iterateActiveAncestry: async (visitor: (entry: any) => unknown) => {
			await visitor(metadata.get("active"));
		},
		iterateEntries: async (_options: unknown, visitor: (entry: any, details: any) => unknown) => {
			await visitor(activeEntry, metadata.get("active"));
			await visitor(abandonedEntry, metadata.get("abandoned"));
		},
	};
	let recallTool: any;
	registerRecallTool({
		registerTool(tool: any): void {
			recallTool = tool;
		},
	} as any);
	assert(recallTool, "Blackhole must register the recall tool");
	const recallCtx = { sessionManager: recallSessionManager };
	const allExpansion = await recallTool.execute(
		"fixture-call",
		{ query: "#1", scope: "all" },
		new AbortController().signal,
		undefined,
		recallCtx,
	);
	assert.match(allExpansion.content[0].text, /abandoned payload/);
	const lineageExpansion = await recallTool.execute(
		"fixture-call",
		{ query: "#1", scope: "lineage" },
		new AbortController().signal,
		undefined,
		recallCtx,
	);
	assert.match(lineageExpansion.content[0].text, /outside active lineage/);
} finally {
	makeTreeWritable(workdir);
	rmSync(workdir, { recursive: true, force: true });
}
