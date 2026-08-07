import assert from "node:assert/strict";
import {
	closeSync,
	cpSync,
	mkdirSync,
	mkdtempSync,
	openSync,
	readFileSync,
	rmSync,
	symlinkSync,
	writeFileSync,
	writeSync,
} from "node:fs";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock } from "node:test";

const packageRoot = process.env.PI_GOAL_X_ROOT;
assert(packageRoot, "PI_GOAL_X_ROOT must name the packaged Goal-X root");
const codingAgentRoot = process.env.PI_CODING_AGENT_ROOT;
assert(
	codingAgentRoot,
	"PI_CODING_AGENT_ROOT must name the packaged Pi coding-agent root",
);

const requestedEvents = Number.parseInt(
	process.env.PI_GOAL_X_LEDGER_EVENTS ?? "25000",
	10,
);
assert(
	Number.isSafeInteger(requestedEvents) && requestedEvents >= 100,
	"event count must be at least 100",
);

const goalSource = readFileSync(
	join(packageRoot, "extensions/goal.ts"),
	"utf8",
);
assert(
	!goalSource.includes("sessionManager.getBranch()"),
	"Goal-X must not hydrate the session branch",
);
assert(
	goalSource.includes('getLatestCustomEntry(FOCUS_ENTRY, { scope: "active" })'),
);
assert(
	goalSource.includes('getLatestCustomEntry(STATE_ENTRY, { scope: "active" })'),
);
assert.equal(
	goalSource.match(/pi\.appendEntry\(STATE_ENTRY/g)?.length,
	1,
	"all Goal-X state checkpoints must pass through one ordered persistence path",
);

const workdir = mkdtempSync(join(tmpdir(), "pi-goal-x-bounded-"));
const runtimeRoot = join(workdir, "runtime");
let timersEnabled = false;

type RuntimeTrace = {
	activeWrites: number;
	cwd: string;
	events: string[];
	failActiveWrite: Error | null;
	failStateAppend: Error | null;
	notifications: Array<{ level: string; message: string }>;
	stateEntries: unknown[];
};

const require = createRequire(import.meta.url);
const mutableFs = require("node:fs") as typeof import("node:fs");
const originalRenameSync = mutableFs.renameSync;
let currentTrace: RuntimeTrace | null = null;

try {
	mkdirSync(runtimeRoot, { recursive: true });
	cpSync(join(packageRoot, "extensions"), join(runtimeRoot, "extensions"), {
		recursive: true,
	});
	cpSync(join(packageRoot, "package.json"), join(runtimeRoot, "package.json"));
	const scopedModules = join(runtimeRoot, "node_modules/@earendil-works");
	mkdirSync(scopedModules, { recursive: true });
	symlinkSync(codingAgentRoot, join(scopedModules, "pi-coding-agent"));
	const peerModules = join(codingAgentRoot, "node_modules");
	symlinkSync(
		join(peerModules, "@earendil-works/pi-ai"),
		join(scopedModules, "pi-ai"),
	);
	symlinkSync(
		join(peerModules, "@earendil-works/pi-tui"),
		join(scopedModules, "pi-tui"),
	);
	symlinkSync(
		join(peerModules, "typebox"),
		join(runtimeRoot, "node_modules/typebox"),
	);

	const ledgerModule = await import(
		join(runtimeRoot, "extensions/goal-ledger.ts")
	);
	const { latestAuditorResultForGoal, readGoalLedger, readGoalLedgerForGoal } =
		ledgerModule;

	assert.deepEqual(readGoalLedger({ cwd: join(workdir, "missing-ledger") }), {
		events: [],
		malformed: 0,
		truncated: false,
		validEvents: 0,
	});

	const ledgerWorkdir = join(workdir, "ledger");
	const ledgerDir = join(ledgerWorkdir, ".pi/goals");
	mkdirSync(ledgerDir, { recursive: true });
	const ledgerPath = join(ledgerDir, "goal_events.jsonl");
	const fd = openSync(ledgerPath, "w");
	try {
		let batch = "";
		for (let i = 0; i < requestedEvents; i++) {
			const event =
				i === 0
					? {
							type: "completion_requested",
							goalId: "target",
							summary: "old request",
							at: `t-${i}`,
						}
					: i === requestedEvents - 1
						? {
								type: "audit_result",
								goalId: "target",
								verdict: "disapproved",
								report: "latest rejection",
								at: `t-${i}`,
							}
						: {
								type: "task_complete",
								goalId: i % 2 === 0 ? "target" : "other",
								taskId: `task-${i}`,
								at: `t-${i}`,
							};
			batch += `${JSON.stringify(event)}\n`;
			if (i % 1024 === 1023) {
				writeSync(fd, batch);
				batch = "";
			}
		}
		if (batch) writeSync(fd, batch);
	} finally {
		closeSync(fd);
	}

	const rssBefore = process.memoryUsage.rss();
	const bounded = readGoalLedger({ cwd: ledgerWorkdir }, { maxEvents: 32 });
	const target = readGoalLedgerForGoal({ cwd: ledgerWorkdir }, "target", {
		maxEvents: 8,
	});
	const rssAfter = process.memoryUsage.rss();

	assert.equal(bounded.validEvents, requestedEvents);
	assert.equal(bounded.events.length, 32);
	assert.equal(bounded.truncated, true);
	assert.equal(target.events.length, 8);
	assert.equal(target.truncated, true);
	assert.equal(
		target.hasCompletionRequested,
		true,
		"the streaming reducer must preserve old completion requests",
	);
	assert.deepEqual(latestAuditorResultForGoal(target.events, "target"), {
		verdict: "disapproved",
		report: "latest rejection",
		at: `t-${requestedEvents - 1}`,
	});

	const failingLedgerDir = join(workdir, "failing-ledger/.pi/goals");
	mkdirSync(failingLedgerDir, { recursive: true });
	symlinkSync("goal_events.jsonl", join(failingLedgerDir, "goal_events.jsonl"));
	assert.throws(
		() => readGoalLedger({ cwd: join(workdir, "failing-ledger") }),
		(error: unknown) => (error as NodeJS.ErrnoException).code === "ELOOP",
		"non-ENOENT ledger open failures must propagate",
	);

	mutableFs.renameSync = ((oldPath, newPath) => {
		const trace = currentTrace;
		const destination = String(newPath);
		if (
			trace &&
			destination.startsWith(join(trace.cwd, ".pi/goals/active_goal_"))
		) {
			trace.events.push("active-file-attempt");
			if (trace.failActiveWrite) {
				const error = trace.failActiveWrite;
				trace.failActiveWrite = null;
				throw error;
			}
			originalRenameSync(oldPath, newPath);
			trace.activeWrites++;
			trace.events.push("active-file");
			return;
		}
		originalRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();

	mock.timers.enable({
		apis: ["Date", "setTimeout"],
		now: Date.parse("2026-08-06T12:00:00.000Z"),
	});
	timersEnabled = true;

	const { default: goalExtension } = await import(
		join(runtimeRoot, "extensions/goal.ts")
	);
	const { parseGoalFile } = await import(
		join(runtimeRoot, "extensions/storage/goal-files.ts")
	);

	function createHarness(label: string, options: { hasUI?: boolean } = {}) {
		const cwd = join(workdir, label);
		const activePath = ".pi/goals/active_goal_2026080612000000_target.md";
		const absoluteActivePath = join(cwd, activePath);
		mkdirSync(join(cwd, ".pi/goals"), { recursive: true });
		const timestamp = new Date(Date.now()).toISOString();
		const goal = {
			id: "target",
			objective: "exercise bounded accounting persistence",
			status: "active",
			autoContinue: false,
			usage: { tokensUsed: 0, activeSeconds: 0 },
			sisyphus: false,
			createdAt: timestamp,
			updatedAt: timestamp,
			activePath,
		};
		writeFileSync(
			absoluteActivePath,
			`${JSON.stringify(goal, null, 2)}\n\n# Goal Prompt\n\n${goal.objective}\n\n## Progress\n`,
			"utf8",
		);

		const trace: RuntimeTrace = {
			activeWrites: 0,
			cwd,
			events: [],
			failActiveWrite: null,
			failStateAppend: null,
			notifications: [],
			stateEntries: [],
		};
		const entries: Array<{
			type: "custom";
			customType: string;
			data: unknown;
		}> = [];
		const tools = new Map<
			string,
			{ execute: (...args: unknown[]) => Promise<unknown> }
		>();
		let activeTools: string[] = [];
		const ctx = {
			cwd,
			getSystemPrompt: () => "",
			hasPendingMessages: () => false,
			hasUI: options.hasUI ?? false,
			isIdle: () => true,
			sessionManager: {
				getLatestCustomEntry(customType: string) {
					return entries.findLast((entry) => entry.customType === customType);
				},
			},
			ui: {
				confirm: async () => false,
				notify(message: string, level: string) {
					trace.notifications.push({ level, message });
				},
				onTerminalInput: () => () => {},
				setStatus() {},
				setWidget() {},
			},
		};
		const handlers = new Map<
			string,
			Array<(event: unknown, ctx: typeof ctx) => unknown>
		>();

		goalExtension({
			appendEntry(customType: string, data: unknown) {
				if (customType === "pi-goal-state") {
					trace.events.push("checkpoint-attempt");
					if (trace.failStateAppend) {
						const error = trace.failStateAppend;
						trace.failStateAppend = null;
						throw error;
					}
					trace.stateEntries.push(structuredClone(data));
					trace.events.push("checkpoint");
				}
				entries.push({
					type: "custom",
					customType,
					data: structuredClone(data),
				});
			},
			getActiveTools: () => activeTools,
			on(event: string, handler: (event: unknown, ctx: typeof ctx) => unknown) {
				const eventHandlers = handlers.get(event) ?? [];
				eventHandlers.push(handler);
				handlers.set(event, eventHandlers);
			},
			registerCommand() {},
			registerMessageRenderer() {},
			registerTool(tool: {
				name: string;
				execute: (...args: unknown[]) => Promise<unknown>;
			}) {
				tools.set(tool.name, tool);
			},
			sendMessage() {},
			sendUserMessage() {},
			setActiveTools(next: string[]) {
				activeTools = next;
			},
		} as never);

		return {
			activePath: absoluteActivePath,
			async emit(name: string, event: unknown = {}) {
				for (const handler of handlers.get(name) ?? [])
					await handler(event, ctx);
			},
			readGoal: () => parseGoalFile(absoluteActivePath),
			async runTool(name: string, params: Record<string, unknown>) {
				const tool = tools.get(name);
				assert(tool, `Goal-X did not register ${name}`);
				return tool.execute("test-call", params, undefined, () => {}, ctx);
			},
			trace,
		};
	}

	function assertOrderedFlushes(trace: RuntimeTrace, count: number): void {
		assert.equal(trace.activeWrites, count);
		assert.equal(trace.stateEntries.length, count);
		assert.equal(trace.events.length, count * 4);
		for (let i = 0; i < count; i++) {
			assert.deepEqual(trace.events.slice(i * 4, i * 4 + 4), [
				"active-file-attempt",
				"active-file",
				"checkpoint-attempt",
				"checkpoint",
			]);
		}
	}

	function tickCapturingErrors(milliseconds: number): string[] {
		const errors: string[] = [];
		const originalConsoleError = console.error;
		console.error = (...parts: unknown[]) => {
			errors.push(parts.map(String).join(" "));
		};
		try {
			mock.timers.tick(milliseconds);
		} finally {
			console.error = originalConsoleError;
		}
		return errors;
	}

	const accountingUpdates = 10_000;
	const accountingIntervalMs = 5 * 60 * 1000;
	const cadence = createHarness("cadence");
	currentTrace = cadence.trace;
	await cadence.emit("session_start", { reason: "new" });
	for (let i = 0; i < 100; i++) {
		await cadence.emit("session_compact");
		await cadence.emit("session_tree");
	}
	assertOrderedFlushes(cadence.trace, 0);
	for (let i = 0; i < accountingUpdates; i++) {
		mock.timers.tick(1000);
		await cadence.emit("tool_execution_end");
	}
	const scheduledFlushes = Math.floor(
		accountingUpdates / (accountingIntervalMs / 1000),
	);
	assertOrderedFlushes(cadence.trace, scheduledFlushes);
	await cadence.emit("session_shutdown");
	assertOrderedFlushes(cadence.trace, scheduledFlushes + 1);
	assert.equal(cadence.readGoal()?.usage.activeSeconds, accountingUpdates);
	mock.timers.tick(accountingIntervalMs);
	assertOrderedFlushes(cadence.trace, scheduledFlushes + 1);

	const scheduledActiveFailure = createHarness(
		"scheduled-active-write-failure",
		{
			hasUI: true,
		},
	);
	currentTrace = scheduledActiveFailure.trace;
	await scheduledActiveFailure.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await scheduledActiveFailure.emit("tool_execution_end");
	scheduledActiveFailure.trace.failActiveWrite = new Error(
		"scheduled-active-write-failure",
	);
	const activeRetryErrors = tickCapturingErrors(accountingIntervalMs - 1000);
	assert.match(
		activeRetryErrors.join("\n"),
		/retrying in five minutes: scheduled-active-write-failure/,
	);
	assert.deepEqual(scheduledActiveFailure.trace.notifications, [
		{
			level: "error",
			message:
				"Goal accounting persistence failed; retrying in five minutes: scheduled-active-write-failure",
		},
	]);
	assert.deepEqual(scheduledActiveFailure.trace.events, [
		"active-file-attempt",
	]);
	assert.equal(scheduledActiveFailure.trace.activeWrites, 0);
	assert.equal(scheduledActiveFailure.trace.stateEntries.length, 0);
	mock.timers.tick(accountingIntervalMs - 1);
	assert.deepEqual(scheduledActiveFailure.trace.events, [
		"active-file-attempt",
	]);
	mock.timers.tick(1);
	assert.deepEqual(scheduledActiveFailure.trace.events, [
		"active-file-attempt",
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);
	assert.equal(scheduledActiveFailure.trace.activeWrites, 1);
	assert.equal(scheduledActiveFailure.trace.stateEntries.length, 1);
	await scheduledActiveFailure.emit("session_shutdown");
	assert.equal(scheduledActiveFailure.trace.activeWrites, 2);
	assert.equal(scheduledActiveFailure.trace.stateEntries.length, 2);
	assert.deepEqual(scheduledActiveFailure.trace.events.slice(-4), [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);

	const scheduledCheckpointFailure = createHarness(
		"scheduled-checkpoint-failure",
	);
	currentTrace = scheduledCheckpointFailure.trace;
	await scheduledCheckpointFailure.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await scheduledCheckpointFailure.emit("tool_execution_end");
	scheduledCheckpointFailure.trace.failStateAppend = new Error(
		"scheduled-checkpoint-failure",
	);
	const checkpointRetryErrors = tickCapturingErrors(
		accountingIntervalMs - 1000,
	);
	assert.match(
		checkpointRetryErrors.join("\n"),
		/retrying in five minutes: scheduled-checkpoint-failure/,
	);
	assert.deepEqual(scheduledCheckpointFailure.trace.events, [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
	]);
	assert.equal(scheduledCheckpointFailure.trace.activeWrites, 1);
	assert.equal(scheduledCheckpointFailure.trace.stateEntries.length, 0);
	mock.timers.tick(accountingIntervalMs - 1);
	assert.equal(scheduledCheckpointFailure.trace.events.length, 3);
	mock.timers.tick(1);
	assert.deepEqual(scheduledCheckpointFailure.trace.events, [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);
	assert.equal(scheduledCheckpointFailure.trace.activeWrites, 2);
	assert.equal(scheduledCheckpointFailure.trace.stateEntries.length, 1);
	await scheduledCheckpointFailure.emit("session_shutdown");
	assert.equal(scheduledCheckpointFailure.trace.activeWrites, 3);
	assert.equal(scheduledCheckpointFailure.trace.stateEntries.length, 2);
	assert.deepEqual(scheduledCheckpointFailure.trace.events.slice(-4), [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);

	const transition = createHarness("forced-transition");
	currentTrace = transition.trace;
	await transition.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await transition.emit("tool_execution_end");
	await transition.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	await transition.runTool("pause_goal", {
		reason: "waiting for test authority",
	});
	assertOrderedFlushes(transition.trace, 1);
	assert.equal(transition.readGoal()?.status, "paused");
	assert.equal(
		(transition.trace.stateEntries[0] as { goal?: { status?: string } }).goal
			?.status,
		"paused",
	);
	mock.timers.tick(accountingIntervalMs);
	assertOrderedFlushes(transition.trace, 1);

	const activeFailure = createHarness("active-write-failure");
	currentTrace = activeFailure.trace;
	await activeFailure.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await activeFailure.emit("tool_execution_end");
	await activeFailure.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	activeFailure.trace.failActiveWrite = new Error("active-write-failure");
	await assert.rejects(
		activeFailure.runTool("pause_goal", { reason: "force a write failure" }),
		/active-write-failure/,
	);
	assert.equal(activeFailure.trace.activeWrites, 0);
	assert.equal(activeFailure.trace.stateEntries.length, 0);
	assert.deepEqual(activeFailure.trace.events, ["active-file-attempt"]);
	assert.equal(activeFailure.readGoal()?.status, "active");
	mock.timers.tick(accountingIntervalMs);
	assert.equal(activeFailure.trace.events.length, 1);

	const checkpointFailure = createHarness("checkpoint-failure");
	currentTrace = checkpointFailure.trace;
	await checkpointFailure.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await checkpointFailure.emit("tool_execution_end");
	await checkpointFailure.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	checkpointFailure.trace.failStateAppend = new Error("checkpoint-failure");
	await assert.rejects(
		checkpointFailure.runTool("pause_goal", {
			reason: "force a checkpoint failure",
		}),
		/checkpoint-failure/,
	);
	assert.equal(checkpointFailure.trace.activeWrites, 1);
	assert.equal(checkpointFailure.trace.stateEntries.length, 0);
	assert.deepEqual(checkpointFailure.trace.events, [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
	]);
	assert.equal(checkpointFailure.readGoal()?.status, "paused");
	mock.timers.tick(accountingIntervalMs);
	assert.equal(checkpointFailure.trace.events.length, 3);

	console.log(
		JSON.stringify({
			accountingUpdates,
			activeFileWrites: cadence.trace.activeWrites,
			boundedEvents: bounded.events.length,
			ledgerBytes: readFileSync(ledgerPath).byteLength,
			ledgerEvents: requestedEvents,
			rssDeltaBytes: rssAfter - rssBefore,
			sessionCheckpoints: cadence.trace.stateEntries.length,
			targetEvents: target.events.length,
		}),
	);
} finally {
	currentTrace = null;
	if (timersEnabled) mock.timers.reset();
	mutableFs.renameSync = originalRenameSync;
	syncBuiltinESMExports();
	rmSync(workdir, { recursive: true, force: true });
}
