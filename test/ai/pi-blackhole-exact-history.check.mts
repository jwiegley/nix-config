import assert from "node:assert/strict";

const root = process.env.PI_BLACKHOLE_ROOT;
if (!root) throw new Error("PI_BLACKHOLE_ROOT is required");

const {
	formatTouchedHistoryPage,
	messagesByOrdinal,
	recentHistory,
	searchHistory,
	touchedHistory,
} = await import(`${root}/src/core/streaming-history.ts`);
const {
	memoryLedgerEntries,
	rawTokensAfterMarkerStreaming,
	rawTokensSinceLastCompactionStreaming,
	recallMemorySourcesStreaming,
	relatedMemoryForEntryIds,
} = await import(`${root}/src/core/streaming-memory.ts`);
const { expandEntryFile } = await import(`${root}/src/core/drill-down.ts`);
const { renderMessage } = await import(`${root}/src/core/render-entries.ts`);
const { formatTouchedOutput } = await import(`${root}/src/core/format-recall.ts`);
const { getTouchedFiles, searchEntries } = await import(`${root}/src/core/search-entries.ts`);
const { recallMemorySources } = await import(`${root}/src/om/ledger/recall.ts`);
const { fullProjection, visibleProjection } = await import(`${root}/src/om/ledger/projection.ts`);
const {
	findObservationsForEntryIds,
	findReflectionsForEntryIds,
} = await import(`${root}/src/om/reverse-recall.ts`);

type Entry = {
	type: string;
	id: string;
	parentId: string | null;
	customType?: string;
	data?: unknown;
	message?: any;
	firstKeptEntryId?: string;
};

type Metadata = {
	ordinal: number;
	messageOrdinal?: number;
	id: string;
	type: string;
	customType?: string;
};

class FixtureHistory {
	readonly entries: Entry[];
	readonly byId: Map<string, Entry>;
	readonly metadata: Map<string, Metadata>;
	readonly leafId: string;

	constructor(entries: Entry[], leafId: string) {
		this.entries = entries;
		this.byId = new Map(entries.map((entry) => [entry.id, entry]));
		this.metadata = new Map();
		let messageOrdinal = 0;
		entries.forEach((entry, ordinal) => {
			this.metadata.set(entry.id, {
				ordinal,
				messageOrdinal: entry.type === "message" ? messageOrdinal++ : undefined,
				id: entry.id,
				type: entry.type,
				customType: entry.customType,
			});
		});
		this.leafId = leafId;
	}

	getEntry(id: string): Entry | undefined {
		return this.byId.get(id);
	}

	getEntryMetadata(id: string): Metadata | undefined {
		return this.metadata.get(id);
	}

	getMessageByOrdinal(target: number): Entry | undefined {
		return this.entries.find((entry) => this.metadata.get(entry.id)?.messageOrdinal === target);
	}

	getSessionFile(): string {
		return "fixture.jsonl";
	}

	async iterateEntries(options: any, visitor: (entry: Entry, metadata: Metadata) => void | Promise<void>): Promise<void> {
		const ordered = options.direction === "reverse" ? [...this.entries].reverse() : this.entries;
		let visited = 0;
		for (const entry of ordered) {
			if (options.type && entry.type !== options.type) continue;
			if (options.customType && entry.customType !== options.customType) continue;
			if (visited >= (options.limit ?? Number.MAX_SAFE_INTEGER)) break;
			await visitor(entry, this.metadata.get(entry.id)!);
			visited++;
		}
	}

	async iterateActiveAncestry(visitor: (metadata: Metadata) => void | Promise<void>): Promise<void> {
		let current: string | null = this.leafId;
		let steps = 0;
		while (current && steps++ <= this.entries.length) {
			const metadata = this.metadata.get(current);
			if (!metadata) break;
			await visitor(metadata);
			current = this.byId.get(current)?.parentId ?? null;
		}
		if (current) throw new Error("fixture ancestry cycle");
	}

	activeEntries(): Entry[] {
		const result: Entry[] = [];
		let current: string | null = this.leafId;
		while (current) {
			const entry = this.byId.get(current);
			if (!entry) break;
			result.push(entry);
			current = entry.parentId;
		}
		return result.reverse();
	}
}

const user = (id: string, parentId: string | null, text: string): Entry => ({
	type: "message",
	id,
	parentId,
	message: { role: "user", content: text, timestamp: 1 },
});

const assistant = (id: string, parentId: string, text: string, path?: string): Entry => ({
	type: "message",
	id,
	parentId,
	message: {
		role: "assistant",
		content: path
			? [
					{ type: "toolCall", id: `call-${id}`, name: "write", arguments: { path, content: text } },
					{ type: "text", text },
				]
			: [{ type: "text", text }],
		api: "anthropic-messages",
		provider: "fixture",
		model: "fixture",
		usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { total: 0 } },
		stopReason: "stop",
		timestamp: 1,
	},
});

const custom = (id: string, parentId: string, customType: string, data: unknown): Entry => ({
	type: "custom",
	id,
	parentId,
	customType,
	data,
});

const entries: Entry[] = [
	user("m0", null, "alpha beta opening"),
	assistant("m1", "m0", "needle first\nsecond line", "/work/first.ts"),
	assistant("abandoned", "m0", "needle abandoned", "/work/abandoned.ts"),
	user("m2", "m1", "gamma alpha request"),
	custom("o1", "m2", "om.observations.recorded", {
		observations: [{
			id: "aaaaaaaaaaaa",
			content: "remember first write",
			timestamp: "2026-01-01T00:00:00Z",
			relevance: "high",
			sourceEntryIds: ["m1"],
			tokenCount: 4,
		}],
		coversUpToId: "m2",
	}),
	assistant("m3", "o1", "needle final alpha", "/work/final.ts"),
	custom("r1", "m3", "om.reflections.recorded", {
		reflections: [{
			id: "bbbbbbbbbbbb",
			content: "writes recur",
			supportingObservationIds: ["aaaaaaaaaaaa"],
			tokenCount: 3,
		}],
		coversUpToId: "m3",
	}),
	custom("d1", "r1", "om.observations.dropped", {
		observationIds: ["aaaaaaaaaaaa"],
		coversUpToId: "m3",
	}),
];
const fixture = new FixtureHistory(entries, "d1");
const active = fixture.activeEntries();
const activeMessages = active.filter((entry) => entry.type === "message");
const renderedActive = activeMessages.map((entry) => {
	const ordinal = fixture.getEntryMetadata(entry.id)!.messageOrdinal!;
	return renderMessage(entry.message, ordinal, entry.id, false);
});
const rawActive = activeMessages.map((entry) => entry.message);

for (const query of ["alpha needle", "needle|gamma"]) {
	const expected = searchEntries(renderedActive, rawActive, query, undefined, "hybrid");
	const actual = await searchHistory(fixture as any, "lineage", query, "hybrid", 1, 5);
	assert.deepEqual(actual.results, expected.slice(0, 5));
	assert.equal(actual.totalMatches, expected.length);
}

const allMessages = entries.filter((entry) => entry.type === "message");
const renderedAll = allMessages.map((entry) => {
	const ordinal = fixture.getEntryMetadata(entry.id)!.messageOrdinal!;
	return renderMessage(entry.message, ordinal, entry.id, false);
});
const rawAll = allMessages.map((entry) => entry.message);
const expectedAll = searchEntries(renderedAll, rawAll, "needle", undefined, "hybrid");
const actualAll = await searchHistory(fixture as any, "all", "needle", "hybrid", 1, 2);
assert.deepEqual(actualAll.results, expectedAll.slice(0, 2));
assert.equal(actualAll.totalMatches, expectedAll.length);
assert.equal(actualAll.totalPages, Math.ceil(expectedAll.length / 2));

const touchedExpected = formatTouchedOutput(getTouchedFiles(rawActive, renderedActive), 1);
const touchedActual = formatTouchedHistoryPage(await touchedHistory(fixture as any, "lineage", 1));
assert.equal(touchedActual, touchedExpected);

const recent = await recentHistory(fixture as any, "lineage", 2);
assert.deepEqual(recent.map((entry: any) => entry.id), ["m2", "m3"]);
const selected = await messagesByOrdinal(fixture as any, "lineage", [1, 2, 3], true);
assert.deepEqual(selected.entries.map((entry: any) => entry.id), ["m1", "m2"]);
assert.deepEqual(selected.invalid, [2]);

const drillDown = expandEntryFile(fixture as any, 1, "first.ts", false);
assert.match(drillDown, /File: \/work\/first\.ts/);
assert.match(drillDown, /needle first/);

const expectedObservations = findObservationsForEntryIds(active as any, ["m1"]);
const expectedReflections = findReflectionsForEntryIds(active as any, ["m1"]);
const related = await relatedMemoryForEntryIds(fixture as any, ["m1"]);
assert.deepEqual(related.observations, expectedObservations);
assert.deepEqual(related.reflections, expectedReflections);
assert.deepEqual(
	await recallMemorySourcesStreaming(fixture as any, "aaaaaaaaaaaa"),
	recallMemorySources(active as any, "aaaaaaaaaaaa"),
);
assert.deepEqual(
	await recallMemorySourcesStreaming(fixture as any, "bbbbbbbbbbbb"),
	recallMemorySources(active as any, "bbbbbbbbbbbb"),
);
const compactLedger = await memoryLedgerEntries(fixture as any);
assert.deepEqual(fullProjection(compactLedger), fullProjection(active as any));
assert.deepEqual(visibleProjection(compactLedger), visibleProjection(active as any));
const fixtureEstimate = (entry: Entry): number => entry.type === "message" ? JSON.stringify(entry.message).length : 0;
const sourceTypes = new Set(["message", "custom_message", "branch_summary"]);
const expectedTokensAfter = (markerId?: string, includeMarker = false): number => {
	const marker = markerId ? active.findIndex((entry) => entry.id === markerId) : -1;
	const start = marker < 0 ? 0 : marker + (includeMarker ? 0 : 1);
	return active.slice(start).reduce(
		(total, entry) => total + (sourceTypes.has(entry.type) ? fixtureEstimate(entry) : 0),
		0,
	);
};
assert.equal(
	await rawTokensAfterMarkerStreaming(
		fixture as any,
		"m2",
		fixtureEstimate,
	),
	expectedTokensAfter("m2"),
);
assert.equal(
	await rawTokensSinceLastCompactionStreaming(fixture as any, fixtureEstimate),
	expectedTokensAfter(),
);

const compactionFixture = (firstKeptEntryId: string): FixtureHistory => {
	const compactedEntries: Entry[] = [
		user("c0", null, "before compaction"),
		{ type: "compaction", id: "c1", parentId: "c0", firstKeptEntryId },
		user("c2", "c1", "first retained"),
		user("c3", "c2", "after compaction"),
	];
	return new FixtureHistory(compactedEntries, "c3");
};
const expectedRetainedTokens = [
	user("c2", "c1", "first retained"),
	user("c3", "c2", "after compaction"),
].reduce((total, entry) => total + fixtureEstimate(entry), 0);
assert.equal(
	await rawTokensSinceLastCompactionStreaming(compactionFixture("c2") as any, fixtureEstimate),
	expectedRetainedTokens,
);
assert.equal(
	await rawTokensSinceLastCompactionStreaming(compactionFixture("missing") as any, fixtureEstimate),
	expectedRetainedTokens,
);

const adversarialText = `literal (a+)+$\n${"a".repeat(20)}!`;
const adversarialFixture = new FixtureHistory(
	[user("regex", null, adversarialText)],
	"regex",
);
const adversarialStarted = performance.now();
await assert.rejects(
	searchHistory(
		adversarialFixture as any,
		"lineage",
		"(a+)+$",
		"hybrid",
		1,
		5,
	),
	/grouped, quantified, or backreference patterns/,
);
assert(
	performance.now() - adversarialStarted < 500,
	"unsafe regex fallback must remain bounded",
);
await assert.rejects(
	searchHistory(
		adversarialFixture as any,
		"lineage",
		"x".repeat(4097),
		"hybrid",
		1,
		5,
	),
	/Recall query exceeds 4096 characters/,
);

class SyntheticHistory {
	readonly count: number;
	constructor(count: number) {
		this.count = count;
	}
	private entry(index: number): Entry {
		return user(`s${index}`, index === 0 ? null : `s${index - 1}`, `ordinary payload ${index} needle-${index}`);
	}
	private metadata(index: number): Metadata {
		return { ordinal: index, messageOrdinal: index, id: `s${index}`, type: "message" };
	}
	getEntry(id: string): Entry | undefined {
		const index = Number(id.slice(1));
		return Number.isSafeInteger(index) && index >= 0 && index < this.count ? this.entry(index) : undefined;
	}
	getEntryMetadata(id: string): Metadata | undefined {
		const index = Number(id.slice(1));
		return Number.isSafeInteger(index) && index >= 0 && index < this.count ? this.metadata(index) : undefined;
	}
	getMessageByOrdinal(index: number): Entry | undefined {
		return index >= 0 && index < this.count ? this.entry(index) : undefined;
	}
	async iterateEntries(options: any, visitor: (entry: Entry, metadata: Metadata) => void | Promise<void>): Promise<void> {
		const reverse = options.direction === "reverse";
		const limit = Math.min(this.count, options.limit ?? this.count);
		for (let visited = 0; visited < limit; visited++) {
			const index = reverse ? this.count - 1 - visited : visited;
			await visitor(this.entry(index), this.metadata(index));
		}
	}
	async iterateActiveAncestry(visitor: (metadata: Metadata) => void | Promise<void>): Promise<void> {
		for (let index = this.count - 1; index >= 0; index--) await visitor(this.metadata(index));
	}
}

const scaleMessages = Math.max(1, Number(process.env.PI_BLACKHOLE_SCALE_MESSAGES ?? 25_000));
const scale = new SyntheticHistory(scaleMessages);
const before = process.memoryUsage().rss;
const scaleResult = await searchHistory(scale as any, "all", `needle-${scaleMessages - 1}\\b`, "hybrid", 1, 5);
const after = process.memoryUsage().rss;
assert.equal(scaleResult.totalMatches, 1);
assert.equal(scaleResult.results[0]?.index, scaleMessages - 1);
assert.ok(after - before < 192 * 1024 * 1024, `streaming search RSS grew by ${after - before} bytes`);

console.log(JSON.stringify({
	exactHistory: true,
	scaleMessages,
	rssDeltaBytes: after - before,
	matchIndex: scaleResult.results[0]?.index,
}));
