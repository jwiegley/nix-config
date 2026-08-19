import assert from "node:assert/strict";
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [
	quietIndexPath,
	quietCompactionPath,
	openaiIndexPath,
	activeHistoryPath,
	customStreamPath,
	openaiWsStreamPath,
	openaiStatePath,
] = process.argv.slice(2);
assert.ok(
	quietIndexPath &&
		quietCompactionPath &&
		openaiIndexPath &&
		activeHistoryPath &&
		customStreamPath &&
		openaiWsStreamPath &&
		openaiStatePath,
	"expected packaged extension paths",
);

const openaiSource = fs.readFileSync(openaiIndexPath, "utf8");
const customStreamSource = fs.readFileSync(customStreamPath, "utf8");
const openaiWsStreamSource = fs.readFileSync(openaiWsStreamPath, "utf8");

assert.equal(
	(openaiSource.match(/sessionManager\.getBranch\s*\(/g) ?? []).length,
	0,
	"pi-openai-server-compaction retains an automatic whole-branch read",
);
assert.equal(
	(openaiSource.match(/sessionManager\.buildSessionContext\s*\(/g) ?? []).length,
	0,
	"pi-openai-server-compaction rebuilds the full active context after every response",
);
assert.equal(
	(openaiSource.match(/sessionManager\.getActiveContextEntries\s*\(/g) ?? []).length,
	1,
	"remote-state reconstruction must use one bounded active projection",
);
assert.match(openaiSource, /selectCompactionLineage\(/, "remote state must exclude retained pre-compaction entries");
const compactionHandlerSource = openaiSource.slice(
	openaiSource.indexOf('pi.on("session_before_compact"'),
	openaiSource.indexOf('pi.on("message_end"'),
);
assert.ok(compactionHandlerSource.length > 0, "missing session_before_compact handler");
assert.equal(
	(compactionHandlerSource.match(/\n\s+headers,\n/g) ?? []).length,
	2,
	"local and remote compaction must share normalized concrete headers",
);
assert.doesNotMatch(
	compactionHandlerSource,
	/headers:\s*auth\.headers/,
	"ProviderHeaders leaked into a concrete-header compaction call",
);
assert.match(
	customStreamSource,
	/setRequestContextLength\(options\.sessionId, context\.messages\.length\)/,
	"provider entrypoint must capture the exact request-time message count",
);
assert.equal(
	(openaiWsStreamSource.match(/capturedContextLength \+ 1/g) ?? []).length,
	2,
	"WebSocket continuation baselines must include the finalized pending assistant",
);
const httpFallbackSource = openaiWsStreamSource.slice(
	openaiWsStreamSource.indexOf("async function fallbackToHttp("),
	openaiWsStreamSource.indexOf("async function fallbackToHttpResponses("),
);
const originalPayloadCallbackIndex = httpFallbackSource.indexOf("await originalOnPayload");
const continuationSliceIndex = httpFallbackSource.indexOf(
	"context.messages.slice(continuationState.contextLength)",
);
assert.ok(originalPayloadCallbackIndex >= 0, "HTTP fallback dropped the original payload callback");
assert.ok(continuationSliceIndex >= 0, "HTTP fallback dropped continuation slicing");
assert.ok(
	originalPayloadCallbackIndex < continuationSliceIndex,
	"HTTP fallback sliced before previous_response_id was attached",
);

const { completedContextLength, selectCompactionLineage } = await import(pathToFileURL(activeHistoryPath));
const keptRoot = { type: "message", id: "kept-root", message: { role: "user", content: "kept" } };
const keptTail = { ...keptRoot, id: "kept-tail", parentId: keptRoot.id };
const compaction = {
	type: "compaction",
	id: "compact",
	parentId: keptTail.id,
	details: { remoteCompaction: { replacementHistory: ["opaque"] } },
};
const postUser = { type: "message", id: "post-user", parentId: compaction.id };
const postAssistant = { type: "message", id: "post-assistant", parentId: postUser.id };
const activeProjection = [compaction, keptRoot, keptTail, postUser, postAssistant];
assert.deepEqual(
	selectCompactionLineage(activeProjection, compaction).map((entry) => entry.id),
	[compaction.id, postUser.id, postAssistant.id],
	"retained pre-compaction entries leaked into reconstructed remote history",
);

const providerContext = [
	{ role: "user", content: "summary" },
	{ role: "custom", content: "state" },
	{ role: "user", content: "current" },
];
const completedAssistant = { role: "assistant", content: "done" };
const nextUser = { role: "user", content: "next" };
const continuationBaseline = completedContextLength(providerContext.length);
assert.equal(continuationBaseline, providerContext.length + 1);
assert.deepEqual(
	[...providerContext, completedAssistant, nextUser].slice(continuationBaseline),
	[nextUser],
	"continuation baseline retransmitted the finalized assistant",
);
for (const invalid of [undefined, -1, 0.5, Number.MAX_SAFE_INTEGER]) {
	assert.equal(completedContextLength(invalid), undefined, `accepted invalid request context length ${invalid}`);
}
assert.equal(completedContextLength(Number.MAX_SAFE_INTEGER - 1), Number.MAX_SAFE_INTEGER);

const {
	clearAllContinuationState,
	clearContinuationState,
	getContinuationState,
	setContinuationState,
	setRequestContextLength,
	takeRequestContextLength,
} = await import(pathToFileURL(openaiStatePath));

setRequestContextLength("one-shot", 7);
assert.equal(takeRequestContextLength("one-shot"), 7);
assert.equal(takeRequestContextLength("one-shot"), undefined, "request context length was not consumed");
setRequestContextLength("session-clear", 8);
clearContinuationState("session-clear");
assert.equal(takeRequestContextLength("session-clear"), undefined, "session cleanup retained a request baseline");
setRequestContextLength("global-clear", 9);
clearAllContinuationState();
assert.equal(takeRequestContextLength("global-clear"), undefined, "shutdown cleanup retained a request baseline");

function makeEventRegistry() {
	const handlers = new Map();
	return {
		handlers,
		on(type, handler) {
			const registered = handlers.get(type) ?? [];
			registered.push(handler);
			handlers.set(type, registered);
		},
		async emit(type, event, context) {
			for (const handler of handlers.get(type) ?? []) await handler(event, context);
		},
	};
}

const openaiEvents = makeEventRegistry();
let registeredProvider;
const { default: openaiExtension, withoutDeletedHeaders } = await import(pathToFileURL(openaiIndexPath));
assert.equal(withoutDeletedHeaders(undefined), undefined);
assert.equal(withoutDeletedHeaders({}), undefined);
assert.equal(withoutDeletedHeaders({ "x-deleted": null }), undefined);
assert.deepEqual(
	withoutDeletedHeaders({ "x-retained": "yes", "x-deleted": null }),
	{ "x-retained": "yes" },
	"provider header deletion markers reached concrete-header APIs",
);
openaiExtension({
	on: openaiEvents.on,
	registerProvider(provider, registration) {
		assert.equal(provider, "openai");
		registeredProvider = registration;
	},
});
assert.equal(typeof registeredProvider?.streamSimple, "function", "OpenAI provider override was not registered");
assert.equal(openaiEvents.handlers.get("message_end")?.length, 1, "expected one OpenAI message_end handler");

const sessionId = "runtime-message-end";
const model = { provider: "openai", api: "openai-responses", id: "gpt-test" };
const openaiContext = {
	cwd: process.cwd(),
	model,
	sessionManager: {
		getSessionId: () => sessionId,
	},
};
const assistant = {
	role: "assistant",
	provider: model.provider,
	model: model.id,
	responseId: "resp-finalized",
	stopReason: "stop",
	content: [],
};
setRequestContextLength(sessionId, providerContext.length);
await openaiEvents.emit("message_end", { message: assistant }, openaiContext);
assert.equal(
	getContinuationState(sessionId)?.contextLength,
	providerContext.length + 1,
	"message_end did not include the not-yet-persisted assistant",
);

await openaiEvents.emit(
	"message_end",
	{ message: { ...assistant, responseId: "resp-without-baseline" } },
	openaiContext,
);
assert.equal(getContinuationState(sessionId), undefined, "missing request baseline did not fail closed");

clearContinuationState(sessionId);
setRequestContextLength(sessionId, 11);
await openaiEvents.emit(
	"message_end",
	{ message: { ...assistant, provider: "unrelated" } },
	openaiContext,
);
assert.equal(takeRequestContextLength(sessionId), 11, "unrelated message_end consumed the pending provider baseline");

setContinuationState(sessionId, {
	responseId: "resp-last-valid",
	modelKey: `${model.provider}:${model.api}:${model.id}`,
	updatedAt: Date.now(),
	contextLength: 4,
});
setRequestContextLength(sessionId, 12);
await openaiEvents.emit(
	"message_end",
	{ message: { ...assistant, stopReason: "error", responseId: undefined } },
	openaiContext,
);
assert.equal(takeRequestContextLength(sessionId), undefined, "failed matching response retained a stale baseline");
assert.equal(getContinuationState(sessionId)?.responseId, "resp-last-valid");
assert.equal(getContinuationState(sessionId)?.contextLength, 4);
const failedUser = { role: "user", content: "failed request" };
const failedAssistant = { role: "assistant", stopReason: "error", content: [] };
assert.deepEqual(
	[...providerContext, completedAssistant, failedUser, failedAssistant, nextUser].slice(
		getContinuationState(sessionId)?.contextLength,
	),
	[failedUser, failedAssistant, nextUser],
	"failed response recovery did not replay the exact tail after the last valid response",
);

const azureSessionId = "runtime-azure-without-baseline";
const azureModel = { provider: "azure-openai", api: "azure-openai-responses", id: "gpt-test" };
const azureContext = {
	...openaiContext,
	model: azureModel,
	sessionManager: { getSessionId: () => azureSessionId },
};
setContinuationState(azureSessionId, {
	responseId: "azure-last-valid",
	modelKey: `${azureModel.provider}:${azureModel.api}:${azureModel.id}`,
	updatedAt: Date.now(),
	contextLength: 5,
});
const previousAzureSetting = process.env.PI_OPENAI_SERVER_COMPACTION_AZURE;
process.env.PI_OPENAI_SERVER_COMPACTION_AZURE = "1";
try {
	await openaiEvents.emit(
		"message_end",
		{
			message: {
				...assistant,
				provider: azureModel.provider,
				model: azureModel.id,
				responseId: "azure-without-baseline",
			},
		},
		azureContext,
	);
} finally {
	if (previousAzureSetting === undefined) delete process.env.PI_OPENAI_SERVER_COMPACTION_AZURE;
	else process.env.PI_OPENAI_SERVER_COMPACTION_AZURE = previousAzureSetting;
}
assert.equal(
	getContinuationState(azureSessionId),
	undefined,
	"Azure continuation without an exact request baseline did not fail closed",
);

const { CompactionIndex, planCompaction, roleOf } = await import(pathToFileURL(quietCompactionPath));
const originalRebuild = CompactionIndex.prototype.rebuild;
const originalClear = CompactionIndex.prototype.clear;
const rebuildSnapshots = [];
const clearSnapshots = [];
CompactionIndex.prototype.rebuild = function (rows) {
	const result = originalRebuild.call(this, rows);
	rebuildSnapshots.push(this.getRows().map((row) => row.toolCallId));
	return result;
};
CompactionIndex.prototype.clear = function () {
	const result = originalClear.call(this);
	clearSnapshots.push(this.getRows().length);
	return result;
};

try {
	const quietEvents = makeEventRegistry();
	const { default: quietExtension } = await import(pathToFileURL(quietIndexPath));
	quietExtension({
		on: quietEvents.on,
		registerCommand() {},
		registerToolRenderer() {},
	});

	for (const event of ["session_start", "session_compact", "session_tree", "session_shutdown"]) {
		assert.equal(quietEvents.handlers.get(event)?.length, 1, `expected one Quiet ${event} handler`);
	}

	let activeReads = 0;
	let projection = [];
	const quietContext = {
		sessionManager: {
			getActiveContextEntries() {
				activeReads += 1;
				return projection;
			},
			getBranch() {
				throw new Error("whole-branch read");
			},
		},
	};
	const toolResultEntry = (id) => ({
		type: "message",
		message: {
			role: "toolResult",
			toolCallId: id,
			toolName: "read",
			content: [{ type: "text", text: id }],
			isError: false,
		},
	});

	projection = [toolResultEntry("startup")];
	await quietEvents.emit("session_start", {}, quietContext);
	projection = [toolResultEntry("compacted")];
	await quietEvents.emit("session_compact", {}, quietContext);
	projection = [toolResultEntry("tree")];
	await quietEvents.emit("session_tree", {}, quietContext);
	await quietEvents.emit("message_start", { message: { role: "assistant" } }, quietContext);
	assert.equal(activeReads, 3, "Quiet rebuilt the active context outside lifecycle transitions");
	assert.deepEqual(rebuildSnapshots, [["startup"], ["compacted"], ["tree"]]);
	await quietEvents.emit("session_shutdown", {}, quietContext);
	assert.deepEqual(clearSnapshots, [0], "Quiet shutdown did not release its index");
	assert.equal(activeReads, 3, "Quiet shutdown reread session history");
} finally {
	CompactionIndex.prototype.rebuild = originalRebuild;
	CompactionIndex.prototype.clear = originalClear;
}

const performanceIndex = new CompactionIndex();
const farRows = Array.from({ length: 256 }, (_, index) => ({
	toolCallId: `far-${index}`,
	toolName: "bash",
	quiet: true,
	status: "settled",
	outcomeKind: "success",
}));
performanceIndex.rebuild([
	...farRows,
	{
		toolCallId: "tail-boundary",
		toolName: "",
		quiet: false,
		status: "settled",
		splitter: true,
	},
	{ toolCallId: "tail-a", toolName: "read", quiet: true, status: "pending" },
	{ toolCallId: "tail-b", toolName: "read", quiet: true, status: "settled", outcomeKind: "success" },
]);
const observableRows = performanceIndex.getRows();
let farReads = 0;
for (let index = 0; index < farRows.length; index++) {
	const row = observableRows[index];
	Object.defineProperty(observableRows, index, {
		configurable: true,
		enumerable: true,
		get() {
			farReads += 1;
			return row;
		},
	});
}
performanceIndex.onEnd({
	toolCallId: "tail-a",
	toolName: "read",
	outcomeKind: "success",
});
assert.equal(farReads, 0, "tail mutation rescanned unrelated retained history");
assert.equal(performanceIndex.role("tail-a").role, "hidden");
assert.deepEqual(performanceIndex.role("tail-b"), {
	role: "carrier",
	groupId: "tail-b",
	carrierId: "tail-b",
	memberIds: ["tail-a", "tail-b"],
});

let randomState = 0x5eed;
const random = () => ((randomState = (randomState * 1664525 + 1013904223) >>> 0) / 2 ** 32);
const differentialIndex = new CompactionIndex();
const pendingTools = new Map();
const toolNames = ["read", "grep", "find", "bash", "edit"];
const outcomes = ["success", "soft", "hard"];
let toolSequence = 0;
for (let step = 0; step < 300; step++) {
	const choice = random();
	if (choice < 0.18) {
		differentialIndex.addSplitter();
	} else if (choice < 0.62 || pendingTools.size === 0) {
		const toolCallId = `differential-${toolSequence++}`;
		const toolName = toolNames[Math.floor(random() * toolNames.length)];
		pendingTools.set(toolCallId, toolName);
		differentialIndex.onStart({ toolCallId, toolName });
	} else {
		const pendingIds = [...pendingTools.keys()];
		const toolCallId = pendingIds[Math.floor(random() * pendingIds.length)];
		const toolName = pendingTools.get(toolCallId);
		pendingTools.delete(toolCallId);
		differentialIndex.onEnd({
			toolCallId,
			toolName,
			outcomeKind: outcomes[Math.floor(random() * outcomes.length)],
		});
	}

	const expectedPlan = planCompaction(differentialIndex.getRows());
	for (const row of differentialIndex.getRows()) {
		assert.deepEqual(
			differentialIndex.role(row.toolCallId),
			roleOf(expectedPlan, row.toolCallId),
			`incremental plan diverged at step ${step} for ${row.toolCallId}`,
		);
	}
}
