import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
	closeSync,
	cpSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	lstatSync,
	openSync,
	readdirSync,
	readFileSync,
	renameSync,
	rmSync,
	statSync,
	symlinkSync,
	unlinkSync,
	writeFileSync,
	writeSync,
} from "node:fs";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock } from "node:test";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_GOAL_X_ROOT;
assert(packageRoot, "PI_GOAL_X_ROOT must name the packaged Goal-X root");
const packageVersion = (
	JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8")) as {
		version?: unknown;
	}
).version;
assert(
	packageVersion === "0.27.4" || packageVersion === "0.28.0",
	`review Goal-X bounded-history behavior for ${String(packageVersion)}`,
);
const hasV2Checkpoints = packageVersion === "0.28.0";
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
	join(packageRoot, "extensions/goal-state.ts"),
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
	activeLstats: number;
	activeWrites: number;
	activeWriteFailuresRemaining: number;
	beforeActiveLstat: { remaining: number; run(): void } | null;
	cwd: string;
	events: string[];
	failActiveWrite: Error | null;
	failStateAppend: Error | null;
	stateAppendFailuresRemaining: number;
	notifications: Array<{ level: string; message: string }>;
	sentMessages: Array<{ content: unknown; details: unknown }>;
	stateEntries: unknown[];
};

const require = createRequire(import.meta.url);
const mutableFs = require("node:fs") as typeof import("node:fs");
const originalCloseSync = mutableFs.closeSync;
const originalLstatSync = mutableFs.lstatSync;
const originalLinkSync = mutableFs.linkSync;
const originalOpenSync = mutableFs.openSync;
const originalReadSync = mutableFs.readSync;
const originalRenameSync = mutableFs.renameSync;
const originalWriteSync = mutableFs.writeSync;
type LedgerIoProbe = {
	path: string;
	opens: number;
	readOperations: number;
	bytesRead: number;
	failOpen?: Error;
	failOpenAfterOpens?: number;
	failRead?: Error;
	failReadAfterOperations?: number;
	onFirstRead?: () => void;
};
let ledgerIoProbe: LedgerIoProbe | null = null;
const probedLedgerFds = new Set<number>();
mutableFs.openSync = ((
	filePath: import("node:fs").PathLike,
	flags: import("node:fs").OpenMode,
	mode?: import("node:fs").Mode,
) => {
	const probe = ledgerIoProbe;
	if (probe && String(filePath) === probe.path) {
		const previousOpens = probe.opens++;
		if (
			probe.failOpen &&
			previousOpens >= (probe.failOpenAfterOpens ?? 0)
		) throw probe.failOpen;
	}
	const opened = originalOpenSync(filePath, flags, mode);
	if (probe && String(filePath) === probe.path) probedLedgerFds.add(opened);
	return opened;
}) as typeof mutableFs.openSync;
mutableFs.readSync = ((
	fd: number,
	buffer: NodeJS.ArrayBufferView,
	offset: number,
	length: number,
	position: number | null,
) => {
	const probe = ledgerIoProbe;
	if (probe && probedLedgerFds.has(fd)) {
		if (
			probe.failRead &&
			probe.readOperations >= (probe.failReadAfterOperations ?? 0)
		) throw probe.failRead;
	}
	const read = originalReadSync(fd, buffer, offset, length, position);
	if (probe && probedLedgerFds.has(fd)) {
		probe.readOperations++;
		probe.bytesRead += read;
		const onFirstRead = probe.onFirstRead;
		probe.onFirstRead = undefined;
		onFirstRead?.();
	}
	return read;
}) as typeof mutableFs.readSync;
mutableFs.closeSync = ((fd: number) => {
	probedLedgerFds.delete(fd);
	return originalCloseSync(fd);
}) as typeof mutableFs.closeSync;
syncBuiltinESMExports();
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
	const {
		LEDGER_CHECKPOINT_VERSION,
		MAX_LEDGER_LINE_BYTES,
		appendGoalEvent,
		invalidateGoalLedgerCache,
		latestAuditorResultForGoal,
		readGoalLedger,
		readGoalLedgerForGoal,
		reconstructGoalLedger,
	} = ledgerModule;
	const { buildCompactionSummary } = await import(
		join(runtimeRoot, "extensions/goal-compaction.ts")
	);
	const { GoalWidgetComponent } = await import(
		join(runtimeRoot, "extensions/widgets/goal-widget.ts")
	);

	assert.deepEqual(readGoalLedger({ cwd: join(workdir, "missing-ledger") }), {
		events: [],
		malformed: 0,
		truncated: false,
		validEvents: 0,
	});
	const fifoLedgerWorkdir = join(workdir, "fifo-ledger");
	const fifoLedgerPath = join(fifoLedgerWorkdir, ".pi/goals/goal_events.jsonl");
	mkdirSync(join(fifoLedgerWorkdir, ".pi/goals"), { recursive: true });
	execFileSync("mkfifo", [fifoLedgerPath]);
	const fifoLedgerProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { readGoalLedger } from ${JSON.stringify(pathToFileURL(join(runtimeRoot, "extensions/goal-ledger.ts")).href)}; readGoalLedger({ cwd: ${JSON.stringify(fifoLedgerWorkdir)} });`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual(
		(fifoLedgerProbe.error as NodeJS.ErrnoException | undefined)?.code,
		"ETIMEDOUT",
		"O_NONBLOCK must prevent a FIFO ledger from hanging a read",
	);
	assert.notEqual(fifoLedgerProbe.status, 0);
	assert.match(fifoLedgerProbe.stderr, /not a regular file/i);
	assert.equal(lstatSync(fifoLedgerPath).isFIFO(), true);

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
					: i === 1
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

	const byteCapWorkdir = join(workdir, "byte-cap-ledger");
	mkdirSync(join(byteCapWorkdir, ".pi/goals"), { recursive: true });
	const byteCapPath = join(byteCapWorkdir, ".pi/goals/goal_events.jsonl");
	const largeReport = "x".repeat(256 * 1024);
	writeFileSync(
		byteCapPath,
		`${Array.from({ length: 40 }, (_, index) =>
			JSON.stringify({
				type: "audit_result",
				goalId: "byte-cap",
				verdict: "disapproved",
				report: `${index}:${largeReport}`,
				at: `byte-${index}`,
			}),
		).join("\n")}\n`,
		"utf8",
	);
	const byteBounded = readGoalLedger({ cwd: byteCapWorkdir });
	const byteBoundedGoal = readGoalLedgerForGoal(
		{ cwd: byteCapWorkdir },
		"byte-cap",
		{ maxEvents: 4096 },
	);
	for (const result of [byteBounded, byteBoundedGoal]) {
		assert.equal(result.validEvents, 40);
		assert.equal(result.truncated, true);
		assert.ok(
			Buffer.byteLength(
				`${result.events.map((event) => JSON.stringify(event)).join("\n")}\n`,
			) <=
				8 * 1024 * 1024,
			"retained ledger tails must be bounded by aggregate serialized bytes",
		);
	}

	const archiveOnly = reconstructGoalLedger([
		{
			type: "goal_archived",
			goalId: "archive-boundary",
			archivePath: "archived.md",
			at: "archive-at",
		},
	]);
	assert.equal(
		archiveOnly.terminalGoals.get("archive-boundary")?.latestStatus,
		"unknown",
	);
	assert.equal(
		archiveOnly.terminalGoals.get("archive-boundary")?.completedAt,
		undefined,
	);
	const completedThenArchived = reconstructGoalLedger([
		{ type: "goal_completed", goalId: "archive-boundary", at: "completed-at" },
		{
			type: "goal_archived",
			goalId: "archive-boundary",
			archivePath: "archived.md",
			at: "archive-at",
		},
	]);
	assert.equal(
		completedThenArchived.terminalGoals.get("archive-boundary")?.completedAt,
		"completed-at",
	);
	const compactGoal = {
		id: "target",
		objective: "retain the newest compaction facts",
		status: "active",
		autoContinue: false,
		usage: { tokensUsed: 0, activeSeconds: 0 },
		sisyphus: false,
		createdAt: "compact-created",
		updatedAt: "compact-updated",
	};
	const compactEvents = Array.from({ length: 6 }, (_, index) => ({
		type: "task_complete" as const,
		goalId: "target",
		taskId: `compact-task-${index}`,
		at: `compact-${index}`,
	}));
	const compactSummary = buildCompactionSummary({
		goalsById: new Map([[compactGoal.id, compactGoal]]),
		focusedGoalId: compactGoal.id,
		focusedGoalEvents: compactEvents,
		capEventsPerGoal: 2,
	});
	assert.doesNotMatch(compactSummary, /compact-task-[0-3]/);
	assert.match(compactSummary, /compact-task-4/);
	assert.match(compactSummary, /compact-task-5/);
	const terminalSummary = buildCompactionSummary({
		goalsById: new Map(),
		focusedGoalId: null,
		ledgerEvents: Array.from({ length: 30 }, (_, index) => ({
			type: "goal_completed" as const,
			goalId: `terminal-${index}`,
			at: `terminal-at-${index}`,
		})),
		capTerminalGoals: 5,
	});
	assert.doesNotMatch(terminalSummary, /terminal-24(?:\D|$)/);
	assert.match(terminalSummary, /terminal-25/);
	assert.match(terminalSummary, /terminal-29/);
	assert.match(terminalSummary, /and 25 earlier retained terminal goals/);
	const nonterminalTruncation = buildCompactionSummary({
		goalsById: new Map(),
		focusedGoalId: null,
		ledgerEvents: [{ type: "goal_unfocused", reason: "external", at: "tail" }],
		ledgerTruncated: true,
	});
	assert.match(nonterminalTruncation, /older ledger history lies outside/);
	assert.doesNotMatch(
		nonterminalTruncation,
		/older terminal history lies outside/,
	);
	assert.equal(
		latestAuditorResultForGoal(target.events, "target"),
		undefined,
		"the bounded tail must not be relied on for old auditor state",
	);
	assert.deepEqual(target.latestAuditorResult, {
		verdict: "disapproved",
		report: "latest rejection",
		at: "t-1",
	});

	const passthroughTheme = new Proxy(
		{},
		{
			get: () => (...args: unknown[]) => String(args.at(-1) ?? ""),
		},
	);
	let widgetAuditProgress: Record<string, unknown> | null = null;
	let widgetLedgerSnapshots = 0;
	const ledgerWidget = new GoalWidgetComponent({
		theme: passthroughTheme as never,
		tui: { requestRender() {} } as never,
		getGoal: () => ({
			id: "target",
			objective: "bounded ledger widget",
			status: "active",
			autoContinue: false,
			usage: { tokensUsed: 0, activeSeconds: 0 },
			sisyphus: false,
			createdAt: "widget-created",
			updatedAt: "widget-updated",
		}),
		getOpenGoalCount: () => 1,
		getAuditorProgress: () => widgetAuditProgress as never,
		getSettings: () => ({ disableTasks: false }) as never,
		getDebugMode: () => false,
		getStalled: () => false,
		getLedgerEvents: () => {
			widgetLedgerSnapshots++;
			return readGoalLedgerForGoal({ cwd: ledgerWorkdir }, "target").events;
		},
	});
	ledgerWidget.render(100);
	const widgetProbe: LedgerIoProbe = {
		path: ledgerPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
	};
	ledgerIoProbe = widgetProbe;
	widgetLedgerSnapshots = 0;
	for (let index = 0; index < 20; index++) ledgerWidget.render(100);
	assert.equal(
		widgetLedgerSnapshots,
		20,
		"each normal widget render must compute one ledger snapshot",
	);
	assert(
		widgetProbe.opens <= 20
			&& widgetProbe.readOperations <= 40
			&& widgetProbe.bytesRead <= 20 * 8 * 1024,
		`unchanged widget renders exceeded bounded fingerprint I/O: ${JSON.stringify(widgetProbe)}`,
	);
	const normalRenderIo = {
		opens: widgetProbe.opens,
		reads: widgetProbe.readOperations,
		bytes: widgetProbe.bytesRead,
	};
	widgetAuditProgress = {
		recentOutput: [],
		phase: "running",
		elapsedMs: 0,
		auditorLabel: "test/auditor",
	};
	for (let index = 0; index < 20; index++) ledgerWidget.render(100);
	assert.equal(
		widgetLedgerSnapshots,
		20,
		"audit spinner renders must not compute unused ledger display data",
	);
	assert.deepEqual(
		{ opens: widgetProbe.opens, reads: widgetProbe.readOperations, bytes: widgetProbe.bytesRead },
		normalRenderIo,
		"audit spinner renders must add no ledger I/O",
	);
	widgetAuditProgress = null;

	mutableFs.appendFileSync(
		ledgerPath,
		`${JSON.stringify({
			type: "audit_result",
			goalId: "target",
			verdict: "approved",
			report: "external tail approval",
			at: "t-external-tail",
		})}\n`,
		"utf8",
	);
	widgetProbe.opens = 0;
	widgetProbe.readOperations = 0;
	widgetProbe.bytesRead = 0;
	ledgerWidget.render(100);
	assert(
		widgetProbe.bytesRead < 32 * 1024,
		`one external append reread ${widgetProbe.bytesRead} bytes instead of a bounded anchor plus tail`,
	);
	assert(widgetProbe.opens <= 3);
	assert.deepEqual(
		readGoalLedgerForGoal({ cwd: ledgerWorkdir }, "target").latestAuditorResult,
		{
			verdict: "approved",
			report: "external tail approval",
			at: "t-external-tail",
		},
		"the per-goal checkpoint must observe externally appended exact audit facts",
	);

	invalidateGoalLedgerCache();
	widgetProbe.opens = 0;
	widgetProbe.readOperations = 0;
	widgetProbe.bytesRead = 0;
	const coldCheckpoint = readGoalLedgerForGoal({ cwd: ledgerWorkdir }, "target");
	assert.equal(coldCheckpoint.validEvents, requestedEvents + 1);
	assert(widgetProbe.opens <= 1, `cold checkpoint reuse opened the ledger ${widgetProbe.opens} times`);
	assert(
		widgetProbe.bytesRead <= 8 * 1024,
		`cold checkpoint reuse read ${widgetProbe.bytesRead} ledger bytes`,
	);
	const checkpointPath = join(ledgerDir, ".goal-ledger-checkpoint.json");
	assert(statSync(checkpointPath).size <= 10 * 1024 * 1024);
	const checkpointDocument = JSON.parse(readFileSync(checkpointPath, "utf8")) as {
		format?: unknown;
		goalId?: unknown;
		goals?: unknown;
		events?: unknown[];
	};
	assert.equal(checkpointDocument.format, "goal-ledger-goal-index");
	assert.equal(checkpointDocument.goalId, "target");
	assert.equal("goals" in checkpointDocument, false);
	assert((checkpointDocument.events?.length ?? Number.POSITIVE_INFINITY) <= 4096);

	invalidateGoalLedgerCache();
	writeFileSync(checkpointPath, "{corrupt", "utf8");
	const recoveredCheckpoint = readGoalLedgerForGoal({ cwd: ledgerWorkdir }, "target");
	assert.equal(recoveredCheckpoint.validEvents, requestedEvents + 1);
	assert.equal(
		(JSON.parse(readFileSync(checkpointPath, "utf8")) as { version: number }).version,
		LEDGER_CHECKPOINT_VERSION,
		"a corrupt derived checkpoint must fall back to the ledger and be replaced",
	);
	const tamperedCheckpoint = JSON.parse(
		readFileSync(checkpointPath, "utf8"),
	) as {
		events: unknown[];
		hasCompletionRequested: boolean;
		latestAuditorResult?: {
			verdict: "approved" | "disapproved" | "error";
			report: string;
			at: string;
		};
	};
	tamperedCheckpoint.events = [];
	tamperedCheckpoint.hasCompletionRequested = false;
	tamperedCheckpoint.latestAuditorResult = {
		verdict: "error",
		report: "tampered checkpoint result",
		at: "tampered",
	};
	writeFileSync(checkpointPath, JSON.stringify(tamperedCheckpoint), "utf8");
	invalidateGoalLedgerCache();
	const recoveredTamperedCheckpoint = readGoalLedgerForGoal(
		{ cwd: ledgerWorkdir },
		"target",
	);
	assert.equal(recoveredTamperedCheckpoint.hasCompletionRequested, true);
	assert.deepEqual(recoveredTamperedCheckpoint.latestAuditorResult, {
		verdict: "approved",
		report: "external tail approval",
		at: "t-external-tail",
	});
	assert(recoveredTamperedCheckpoint.events.length > 0);
	assert.equal(recoveredTamperedCheckpoint.validEvents, requestedEvents + 1);
	ledgerIoProbe = null;

	const rewriteWorkdir = join(workdir, "ledger-same-size-rewrite");
	const rewriteDir = join(rewriteWorkdir, ".pi/goals");
	mkdirSync(rewriteDir, { recursive: true });
	const rewritePath = join(rewriteDir, "goal_events.jsonl");
	const rewriteOne = `${JSON.stringify({ type: "audit_result", goalId: "rewrite", verdict: "approved", report: "one", at: "same" })}\n`;
	const rewriteTwo = `${JSON.stringify({ type: "audit_result", goalId: "rewrite", verdict: "approved", report: "two", at: "same" })}\n`;
	assert.equal(Buffer.byteLength(rewriteOne), Buffer.byteLength(rewriteTwo));
	writeFileSync(rewritePath, rewriteOne, "utf8");
	assert.equal(readGoalLedgerForGoal({ cwd: rewriteWorkdir }, "rewrite").latestAuditorResult?.report, "one");
	const rewriteStat = statSync(rewritePath);
	writeFileSync(rewritePath, rewriteTwo, "utf8");
	mutableFs.utimesSync(rewritePath, rewriteStat.atime, rewriteStat.mtime);
	invalidateGoalLedgerCache();
	assert.equal(
		readGoalLedgerForGoal({ cwd: rewriteWorkdir }, "rewrite").latestAuditorResult?.report,
		"two",
		"a same-size rewrite with restored mtime must invalidate the bounded checkpoint",
	);
	const middleRewriteWorkdir = join(workdir, "ledger-middle-same-size-rewrite");
	const middleRewriteDir = join(middleRewriteWorkdir, ".pi/goals");
	mkdirSync(middleRewriteDir, { recursive: true });
	const middleRewritePath = join(middleRewriteDir, "goal_events.jsonl");
	const middlePrefix = Array.from({ length: 150 }, (_, index) =>
		JSON.stringify({ type: "task_complete", goalId: "other", taskId: `prefix-${index}`, at: `prefix-${index}` }),
	).join("\n");
	const middleSuffix = Array.from({ length: 150 }, (_, index) =>
		JSON.stringify({ type: "task_complete", goalId: "other", taskId: `suffix-${index}`, at: `suffix-${index}` }),
	).join("\n");
	const middleOne = `${middlePrefix}\n${rewriteOne}${middleSuffix}\n`;
	const middleTwo = `${middlePrefix}\n${rewriteTwo}${middleSuffix}\n`;
	assert.equal(Buffer.byteLength(middleOne), Buffer.byteLength(middleTwo));
	assert(Buffer.byteLength(middleOne) > 16 * 1024);
	writeFileSync(middleRewritePath, middleOne, "utf8");
	assert.equal(
		readGoalLedgerForGoal({ cwd: middleRewriteWorkdir }, "rewrite").latestAuditorResult?.report,
		"one",
	);
	const middleRewriteStat = statSync(middleRewritePath);
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2);
	writeFileSync(middleRewritePath, middleTwo, "utf8");
	mutableFs.utimesSync(middleRewritePath, middleRewriteStat.atime, middleRewriteStat.mtime);
	invalidateGoalLedgerCache();
	assert.equal(
		readGoalLedgerForGoal({ cwd: middleRewriteWorkdir }, "rewrite").latestAuditorResult?.report,
		"two",
		"a same-size middle rewrite with restored mtime must rebuild on changed ctime",
	);
	writeFileSync(
		rewritePath,
		JSON.stringify({ type: "goal_completed", goalId: "rewrite", at: "short" }),
		"utf8",
	);
	invalidateGoalLedgerCache();
	const truncatedRewrite = readGoalLedgerForGoal({ cwd: rewriteWorkdir }, "rewrite");
	assert.equal(truncatedRewrite.validEvents, 1);
	assert.equal(truncatedRewrite.events[0]?.type, "goal_completed");

	const incrementalTornWorkdir = join(workdir, "ledger-incremental-torn-tail");
	const incrementalTornDir = join(incrementalTornWorkdir, ".pi/goals");
	mkdirSync(incrementalTornDir, { recursive: true });
	const incrementalTornPath = join(incrementalTornDir, "goal_events.jsonl");
	writeFileSync(incrementalTornPath, '{"type":"audit_result","goalId":"torn"', "utf8");
	const incompleteTorn = readGoalLedgerForGoal({ cwd: incrementalTornWorkdir }, "torn");
	assert.equal(incompleteTorn.malformed, 1);
	assert.equal(incompleteTorn.validEvents, 0);
	mutableFs.appendFileSync(
		incrementalTornPath,
		',"verdict":"approved","report":"joined","at":"tail"}',
		"utf8",
	);
	const joinedTorn = readGoalLedgerForGoal({ cwd: incrementalTornWorkdir }, "torn");
	assert.equal(joinedTorn.malformed, 0);
	assert.equal(joinedTorn.validEvents, 1);
	assert.equal(joinedTorn.latestAuditorResult?.report, "joined");

	const concurrentAppendWorkdir = join(workdir, "ledger-concurrent-append");
	const concurrentAppendDir = join(concurrentAppendWorkdir, ".pi/goals");
	mkdirSync(concurrentAppendDir, { recursive: true });
	const concurrentAppendPath = join(concurrentAppendDir, "goal_events.jsonl");
	writeFileSync(
		concurrentAppendPath,
		`${Array.from({ length: 2000 }, (_, index) => JSON.stringify({ type: "task_complete", goalId: "other", taskId: `concurrent-${index}`, at: `concurrent-${index}` })).join("\n")}\n`,
		"utf8",
	);
	const concurrentProbe: LedgerIoProbe = {
		path: concurrentAppendPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
		onFirstRead: () => {
			mutableFs.appendFileSync(
				concurrentAppendPath,
				`${JSON.stringify({ type: "audit_result", goalId: "concurrent", verdict: "approved", report: "arrived during scan", at: "concurrent-tail" })}\n`,
				"utf8",
			);
		},
	};
	ledgerIoProbe = concurrentProbe;
	const concurrentAppend = readGoalLedgerForGoal({ cwd: concurrentAppendWorkdir }, "concurrent");
	ledgerIoProbe = null;
	assert.equal(concurrentAppend.latestAuditorResult?.report, "arrived during scan");
	assert.equal(concurrentAppend.validEvents, 2001);

	const finalSymlinkWorkdir = join(workdir, "ledger-final-symlink");
	const finalSymlinkDir = join(finalSymlinkWorkdir, ".pi/goals");
	const finalSymlinkTarget = join(workdir, "ledger-final-symlink-target.jsonl");
	mkdirSync(finalSymlinkDir, { recursive: true });
	writeFileSync(finalSymlinkTarget, "target-must-not-change\n", "utf8");
	symlinkSync(finalSymlinkTarget, join(finalSymlinkDir, "goal_events.jsonl"));
	const finalSymlinkAppend = appendGoalEvent(
		{ cwd: finalSymlinkWorkdir },
		{ type: "goal_completed", goalId: "symlink", at: "never" },
	);
	assert.equal(finalSymlinkAppend.ok, false);
	assert.equal(readFileSync(finalSymlinkTarget, "utf8"), "target-must-not-change\n");
	assert.throws(
		() => readGoalLedger({ cwd: finalSymlinkWorkdir }),
		/ELOOP|symbolic link|not a regular file/i,
	);

	const ancestorSymlinkWorkdir = join(workdir, "ledger-ancestor-symlink");
	const ancestorRealDir = join(workdir, "ledger-ancestor-target");
	mkdirSync(join(ancestorSymlinkWorkdir, ".pi"), { recursive: true });
	mkdirSync(ancestorRealDir, { recursive: true });
	symlinkSync(ancestorRealDir, join(ancestorSymlinkWorkdir, ".pi/goals"));
	const ancestorSymlinkAppend = appendGoalEvent(
		{ cwd: ancestorSymlinkWorkdir },
		{ type: "goal_completed", goalId: "ancestor", at: "never" },
	);
	assert.equal(ancestorSymlinkAppend.ok, false);
	assert.equal(existsSync(join(ancestorRealDir, "goal_events.jsonl")), false);
	assert.throws(
		() => readGoalLedger({ cwd: ancestorSymlinkWorkdir }),
		/symlink ancestor/i,
	);

	const checkpointSymlinkWorkdir = join(workdir, "checkpoint-final-symlink");
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: checkpointSymlinkWorkdir },
			{ type: "audit_result", goalId: "checkpoint-safe", verdict: "approved", report: "ledger wins", at: "safe" },
		),
		{ ok: true },
	);
	assert.equal(
		readGoalLedgerForGoal({ cwd: checkpointSymlinkWorkdir }, "checkpoint-safe").latestAuditorResult?.report,
		"ledger wins",
	);
	const checkpointSymlinkPath = join(checkpointSymlinkWorkdir, ".pi/goals/.goal-ledger-checkpoint.json");
	const checkpointSymlinkTarget = join(workdir, "checkpoint-symlink-target.json");
	unlinkSync(checkpointSymlinkPath);
	writeFileSync(checkpointSymlinkTarget, "checkpoint-target-must-not-be-read-or-written", "utf8");
	symlinkSync(checkpointSymlinkTarget, checkpointSymlinkPath);
	invalidateGoalLedgerCache();
	assert.equal(
		readGoalLedgerForGoal({ cwd: checkpointSymlinkWorkdir }, "checkpoint-safe").latestAuditorResult?.report,
		"ledger wins",
		"a final checkpoint symlink must fall back to the authoritative ledger",
	);
	assert.equal(
		readFileSync(checkpointSymlinkTarget, "utf8"),
		"checkpoint-target-must-not-be-read-or-written",
	);
	assert.equal(lstatSync(checkpointSymlinkPath).isSymbolicLink(), true);

	const replacementWorkdir = join(workdir, "ledger-replacement-retry");
	const replacementDir = join(replacementWorkdir, ".pi/goals");
	const replacementPath = join(replacementDir, "goal_events.jsonl");
	mkdirSync(replacementDir, { recursive: true });
	writeFileSync(
		replacementPath,
		`${JSON.stringify({ type: "audit_result", goalId: "replace", verdict: "approved", report: "old inode", at: "old" })}\n`,
		"utf8",
	);
	assert.equal(readGoalLedgerForGoal({ cwd: replacementWorkdir }, "replace").latestAuditorResult?.report, "old inode");
	const replacementNextPath = `${replacementPath}.next`;
	writeFileSync(
		replacementNextPath,
		`${JSON.stringify({ type: "audit_result", goalId: "replace", verdict: "approved", report: "new inode", at: "new" })}\n`,
		"utf8",
	);
	invalidateGoalLedgerCache();
	const replacementProbe: LedgerIoProbe = {
		path: replacementPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
		onFirstRead: () => renameSync(replacementNextPath, replacementPath),
	};
	ledgerIoProbe = replacementProbe;
	const replacementRead = readGoalLedgerForGoal({ cwd: replacementWorkdir }, "replace");
	ledgerIoProbe = null;
	assert.equal(
		replacementRead.latestAuditorResult?.report,
		"new inode",
		"an inode replacement between checkpoint validation and tail scan must rebuild within a bounded retry",
	);

	const auditLruWorkdir = join(workdir, "ledger-audit-report-lru");
	const auditLruDir = join(auditLruWorkdir, ".pi/goals");
	const auditLruPath = join(auditLruDir, "goal_events.jsonl");
	mkdirSync(auditLruDir, { recursive: true });
	const aggregateReport = "r".repeat(720 * 1024);
	writeFileSync(
		auditLruPath,
		`${Array.from({ length: 6 }, (_, index) => JSON.stringify({
			type: "audit_result",
			goalId: `audit-lru-${index}`,
			verdict: "disapproved",
			report: `${index}${aggregateReport}`,
			at: `audit-lru-${index}`,
		})).join("\n")}\n`,
		"utf8",
	);
	for (let index = 0; index < 6; index++) {
		assert.equal(
			readGoalLedgerForGoal({ cwd: auditLruWorkdir }, `audit-lru-${index}`, { maxEvents: 1 }).latestAuditorResult?.report[0],
			String(index),
		);
	}
	const auditLruProbe: LedgerIoProbe = {
		path: auditLruPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
	};
	ledgerIoProbe = auditLruProbe;
	readGoalLedgerForGoal({ cwd: auditLruWorkdir }, "audit-lru-0", { maxEvents: 1 });
	ledgerIoProbe = null;
	assert(
		auditLruProbe.bytesRead > 1024 * 1024,
		`aggregate latest-audit reports must count toward the 8 MiB LRU and evict the oldest entry (${auditLruProbe.bytesRead} bytes reread)`,
	);

	const distinctGoalCount = 50_000;
	const cardinalityWorkdir = join(workdir, "ledger-cardinality");
	const cardinalityDir = join(cardinalityWorkdir, ".pi/goals");
	mkdirSync(cardinalityDir, { recursive: true });
	const cardinalityPath = join(cardinalityDir, "goal_events.jsonl");
	const cardinalityFd = openSync(cardinalityPath, "w");
	try {
		let batch = "";
		for (let i = 0; i < distinctGoalCount; i++) {
			batch += `${JSON.stringify({ type: "goal_completed", goalId: `done-${i}`, at: `c-${i}` })}\n`;
			if (i % 1024 === 1023) {
				writeSync(cardinalityFd, batch);
				batch = "";
			}
		}
		if (batch) writeSync(cardinalityFd, batch);
	} finally {
		closeSync(cardinalityFd);
	}
	const collectGarbage = global.gc;
	assert(
		collectGarbage,
		"the Goal-X cardinality check requires Node.js --expose-gc",
	);
	collectGarbage();
	const cardinalityHeapBefore = process.memoryUsage().heapUsed;
	const cardinalityRssBefore = process.memoryUsage().rss;
	const cardinality = readGoalLedger(
		{ cwd: cardinalityWorkdir },
		{ maxEvents: 32 },
	);
	collectGarbage();
	const cardinalityHeapDelta =
		process.memoryUsage().heapUsed - cardinalityHeapBefore;
	const cardinalityRssDelta = process.memoryUsage().rss - cardinalityRssBefore;
	assert.equal(cardinality.validEvents, distinctGoalCount);
	assert.equal(cardinality.events.length, 32);
	assert(
		cardinalityHeapDelta < 4 * 1024 * 1024,
		`distinct historical goal ids retained ${cardinalityHeapDelta} heap bytes`,
	);
	assert(
		cardinalityRssDelta < 40 * 1024 * 1024,
		`distinct historical goal ids retained ${cardinalityRssDelta} RSS bytes`,
	);
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: cardinalityWorkdir },
			{
				type: "goal_unfocused",
				reason: "fixed-cardinality-probe",
				at: "c-tail",
			},
		),
		{ ok: true },
	);
	assert.equal(
		existsSync(join(cardinalityDir, ".goal-ledger-checkpoint.json")),
		false,
		"an append must not materialize an all-goal checkpoint whose size and cost grow with historical goal cardinality",
	);
	const cardinalityAfterAppend = readGoalLedger(
		{ cwd: cardinalityWorkdir },
		{ maxEvents: 32 },
	);
	assert.equal(cardinalityAfterAppend.validEvents, distinctGoalCount + 1);
	assert.deepEqual(cardinalityAfterAppend.events.at(-1), {
		type: "goal_unfocused",
		reason: "fixed-cardinality-probe",
		at: "c-tail",
	});
	assert.equal(
		cardinalityAfterAppend.events.filter(
			(event) =>
				event.type === "goal_unfocused" &&
				event.reason === "fixed-cardinality-probe",
		).length,
		1,
		"the in-process append must extend the bounded tail exactly once",
	);

	for (let index = 0; index < 18; index++) {
		const focused = readGoalLedgerForGoal(
			{ cwd: cardinalityWorkdir },
			`done-${index}`,
			{ maxEvents: 1 },
		);
		assert.equal(focused.completedAt, `c-${index}`);
		assert.equal(focused.events[0]?.type, "goal_completed");
	}
	const checkpointNames = readdirSync(cardinalityDir).filter((name) =>
		name.includes("ledger-checkpoint")
	);
	assert.deepEqual(
		checkpointNames,
		[".goal-ledger-checkpoint.json"],
		"50k distinct historical ids must still produce exactly one durable checkpoint",
	);
	assert(
		statSync(join(cardinalityDir, checkpointNames[0]!)).size <= 10 * 1024 * 1024,
		"the single durable checkpoint must retain its fixed serialized byte ceiling",
	);
	const evictedCardinalityProbe: LedgerIoProbe = {
		path: cardinalityPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
	};
	ledgerIoProbe = evictedCardinalityProbe;
	const evictedCardinality = readGoalLedgerForGoal(
		{ cwd: cardinalityWorkdir },
		"done-0",
		{ maxEvents: 1 },
	);
	ledgerIoProbe = null;
	assert.equal(evictedCardinality.completedAt, "c-0");
	assert(
		evictedCardinalityProbe.bytesRead > 1024 * 1024,
		"a goal absent from both fixed-cardinality caches must perform one exact streaming bootstrap",
	);
	const hotCardinalityProbe: LedgerIoProbe = {
		path: cardinalityPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
	};
	ledgerIoProbe = hotCardinalityProbe;
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: cardinalityWorkdir },
			"done-0",
			{ maxEvents: 1 },
		).completedAt,
		"c-0",
	);
	ledgerIoProbe = null;
	assert(
		hotCardinalityProbe.bytesRead <= 8192,
		`the working-set reread must validate only bounded anchors (${hotCardinalityProbe.bytesRead} bytes)`,
	);

	const failingLedgerDir = join(workdir, "failing-ledger/.pi/goals");
	mkdirSync(failingLedgerDir, { recursive: true });
	symlinkSync("goal_events.jsonl", join(failingLedgerDir, "goal_events.jsonl"));
	assert.throws(
		() => readGoalLedger({ cwd: join(workdir, "failing-ledger") }),
		(error: unknown) => (error as NodeJS.ErrnoException).code === "ELOOP",
		"non-ENOENT ledger open failures must propagate",
	);

	const oversizedWorkdir = join(workdir, "oversized-ledger");
	const oversizedDir = join(oversizedWorkdir, ".pi/goals");
	mkdirSync(oversizedDir, { recursive: true });
	const afterOversized = {
		type: "task_complete",
		goalId: "target",
		taskId: "after-oversized",
		at: "t-oversized",
	};
	writeFileSync(
		join(oversizedDir, "goal_events.jsonl"),
		`${"x".repeat(1024 * 1024 + 1)}\n${JSON.stringify(afterOversized)}\n`,
		"utf8",
	);
	const oversized = readGoalLedger({ cwd: oversizedWorkdir });
	assert.equal(oversized.malformed, 1);
	assert.equal(oversized.validEvents, 1);
	assert.deepEqual(oversized.events, [afterOversized]);

	const oversizedAppendWorkdir = join(workdir, "oversized-append-ledger");
	const oversizedAppendDir = join(oversizedAppendWorkdir, ".pi/goals");
	mkdirSync(oversizedAppendDir, { recursive: true });
	const oversizedAppendPath = join(oversizedAppendDir, "goal_events.jsonl");
	const acceptedBeforeOversize = {
		type: "audit_result" as const,
		goalId: "oversized-append",
		verdict: "disapproved" as const,
		report: "before",
		at: "oversized-before",
	};
	assert.deepEqual(appendGoalEvent({ cwd: oversizedAppendWorkdir }, acceptedBeforeOversize), { ok: true });
	readGoalLedgerForGoal({ cwd: oversizedAppendWorkdir }, "oversized-append");
	const bytesBeforeOversizedAppend = statSync(oversizedAppendPath).size;
	const rejectedOversizedAppend = appendGoalEvent(
		{ cwd: oversizedAppendWorkdir },
		{
			type: "audit_result",
			goalId: "oversized-append",
			verdict: "error",
			report: "x".repeat(MAX_LEDGER_LINE_BYTES + 1),
			at: "oversized-rejected",
		},
	);
	assert.equal(rejectedOversizedAppend.ok, false);
	assert.match(
		String(rejectedOversizedAppend.ok ? "" : rejectedOversizedAppend.error),
		/maximum/,
	);
	assert.equal(statSync(oversizedAppendPath).size, bytesBeforeOversizedAppend);
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: oversizedAppendWorkdir },
			{
				type: "audit_result",
				goalId: "oversized-append",
				verdict: "approved",
				report: "after",
				at: "oversized-after",
			},
		),
		{ ok: true },
	);
	const hotOversizedParity = readGoalLedgerForGoal(
		{ cwd: oversizedAppendWorkdir },
		"oversized-append",
	);
	invalidateGoalLedgerCache();
	const coldOversizedParity = readGoalLedgerForGoal(
		{ cwd: oversizedAppendWorkdir },
		"oversized-append",
	);
	assert.deepEqual(coldOversizedParity, hotOversizedParity);
	assert.equal(coldOversizedParity.validEvents, 2);
	assert.equal(coldOversizedParity.latestAuditorResult?.report, "after");

	const unicodeWorkdir = join(workdir, "unicode-ledger");
	const unicodeDir = join(unicodeWorkdir, ".pi/goals");
	mkdirSync(unicodeDir, { recursive: true });
	const unicodePath = join(unicodeDir, "goal_events.jsonl");
	const unicodePrefix =
		'{"type":"goal_created","goalId":"unicode","objective":"';
	const unicodeSuffix =
		'","sisyphus":false,"autoContinue":false,"at":"t-unicode"}\n';
	const unicodeAsciiCount =
		64 * 1024 - 1 - Buffer.byteLength(unicodePrefix, "utf8");
	assert(unicodeAsciiCount > 0);
	writeFileSync(
		unicodePath,
		`${unicodePrefix}${"a".repeat(unicodeAsciiCount)}é${unicodeSuffix}`,
		"utf8",
	);
	assert.equal(readFileSync(unicodePath)[64 * 1024 - 1], 0xc3);
	const unicode = readGoalLedger({ cwd: unicodeWorkdir }, { maxEvents: 1 });
	assert.equal(unicode.malformed, 0);
	assert.equal(unicode.validEvents, 1);
	assert.equal(unicode.events[0]?.type, "goal_created");
	assert(
		unicode.events[0]?.type === "goal_created" &&
			unicode.events[0].objective.endsWith("é"),
	);

	mutableFs.linkSync = ((oldPath, newPath) => {
		const trace = currentTrace;
		const source = String(oldPath);
		const destination = String(newPath);
		if (
			trace &&
			source.includes(".write-") &&
			source.endsWith("/content") &&
			destination.startsWith(join(trace.cwd, ".pi/goals/active_goal_"))
		) {
			trace.events.push("active-file-attempt");
			if (trace.failActiveWrite) {
				const error = trace.failActiveWrite;
				trace.failActiveWrite = null;
				throw error;
			}
			if (trace.activeWriteFailuresRemaining > 0) {
				trace.activeWriteFailuresRemaining--;
				throw new Error("injected-active-write-failure");
			}
			originalLinkSync(oldPath, newPath);
			trace.activeWrites++;
			trace.events.push("active-file");
			return;
		}
		originalLinkSync(oldPath, newPath);
	}) as typeof mutableFs.linkSync;
	mutableFs.renameSync = ((oldPath, newPath) => {
		const trace = currentTrace;
		const source = String(oldPath);
		const destination = String(newPath);
		if (
			trace
			&& source.includes(".write-")
			&& source.endsWith("/content")
			&& destination.startsWith(join(trace.cwd, ".pi/goals/active_goal_"))
		) {
			trace.events.push("active-file-attempt");
			if (trace.failActiveWrite) {
				const error = trace.failActiveWrite;
				trace.failActiveWrite = null;
				throw error;
			}
			if (trace.activeWriteFailuresRemaining > 0) {
				trace.activeWriteFailuresRemaining--;
				throw new Error("injected-active-write-failure");
			}
			originalRenameSync(oldPath, newPath);
			trace.activeWrites++;
			trace.events.push("active-file");
			return;
		}
		originalRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	const tracingLstatSync = ((filePath, options) => {
		const trace = currentTrace;
		if (
			trace &&
			String(filePath).startsWith(join(trace.cwd, ".pi/goals/active_goal_"))
		) {
			trace.activeLstats++;
			const hook = trace.beforeActiveLstat;
			if (hook) {
				hook.remaining--;
				if (hook.remaining === 0) {
					trace.beforeActiveLstat = null;
					hook.run();
				}
			}
		}
		return originalLstatSync(filePath, options as never);
	}) as typeof mutableFs.lstatSync;
	mutableFs.lstatSync = tracingLstatSync;
	syncBuiltinESMExports();

	mock.timers.enable({
		apis: ["Date", "setTimeout"],
		now: Date.parse("2026-08-06T12:00:00.000Z"),
	});
	timersEnabled = true;

	const { default: goalExtension } = await import(
		join(runtimeRoot, "extensions/goal.ts")
	);
	const {
		archiveGoalFile,
		archivedPathForGoal,
		atomicWriteGoalFile,
		invalidateGoalPoolCache,
		MAX_CHECKED_GOAL_FILE_BYTES,
			MAX_CHECKED_POOL_SNAPSHOT_BYTES,
			parseGoalFile,
			readActiveGoalPool,
			readGoalFileSnapshotChecked,
			recoveredArchivedGoal,
			refreshActiveGoalPoolSnapshot,
		safeUnlinkGoalFile,
		serializeGoalFile,
	} = await import(join(runtimeRoot, "extensions/storage/goal-files.ts"));
	const archiveCurrent = (
		ctx: { cwd: string },
		goal: Parameters<typeof archiveGoalFile>[1],
	) => archiveGoalFile(
		ctx,
		goal,
		readGoalFileSnapshotChecked(ctx, join(ctx.cwd, goal.activePath ?? "")),
	);
	const { runRecoveryRepair, runRecoveryReport } = await import(
		join(runtimeRoot, "extensions/goal-recovery.ts")
	);
	const {
		acquireGoalLock,
		GoalLockRecoveryError,
		MAX_GOAL_LOCK_BYTES,
		recoverStaleGoalLock,
	} = await import(
		join(runtimeRoot, "extensions/storage/goal-lock.ts")
	);
	const { atomicWriteRegularFile, readRegularFile } = await import(
		join(runtimeRoot, "extensions/storage/safe-fs.ts")
	);
	const stripTypesImport = spawnSync(
		process.execPath,
		[
			"--experimental-strip-types",
			"--input-type=module",
			"--eval",
			`await import(${JSON.stringify(pathToFileURL(join(packageRoot, "extensions/storage/goal-lock.ts")).href)})`,
		],
		{ encoding: "utf8", timeout: 10_000 },
	);
	assert.equal(
		stripTypesImport.status,
		0,
		`the package serial strip-types path must import goal-lock.ts: ${stripTypesImport.stderr}`,
	);
	const stableReadWorkdir = join(workdir, "stable-regular-file-read");
	mkdirSync(stableReadWorkdir, { recursive: true });
	const stableReadPath = join(stableReadWorkdir, "stable.txt");
	writeFileSync(stableReadPath, "AAAA", "utf8");
	const stableReadSync = mutableFs.readSync;
	let inPlaceMutated = false;
	mutableFs.readSync = ((
		fd: number,
		buffer: NodeJS.ArrayBufferView,
		offset: number,
		length: number,
		position: number | null,
	) => {
		const count = stableReadSync(fd, buffer, offset, length, position);
		if (!inPlaceMutated && count === 4 && Buffer.from(buffer.buffer, buffer.byteOffset + offset, count).toString("utf8") === "AAAA") {
			inPlaceMutated = true;
			writeFileSync(stableReadPath, "BBBB", "utf8");
		}
		return count;
	}) as typeof mutableFs.readSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => readRegularFile(stableReadWorkdir, stableReadPath, 16),
			/changed while it was being read/,
			"same-inode/same-size mutation during a descriptor read must be rejected",
		);
	} finally {
		mutableFs.readSync = stableReadSync;
		syncBuiltinESMExports();
	}
	writeFileSync(stableReadPath, "CCCC", "utf8");
	const renamedReadSync = mutableFs.readSync;
	let renamedDuringRead = false;
	mutableFs.readSync = ((
		fd: number,
		buffer: NodeJS.ArrayBufferView,
		offset: number,
		length: number,
		position: number | null,
	) => {
		const count = renamedReadSync(fd, buffer, offset, length, position);
		if (!renamedDuringRead && count === 4 && Buffer.from(buffer.buffer, buffer.byteOffset + offset, count).toString("utf8") === "CCCC") {
			renamedDuringRead = true;
			originalRenameSync(stableReadPath, `${stableReadPath}.old`);
			writeFileSync(stableReadPath, "DDDD", "utf8");
		}
		return count;
	}) as typeof mutableFs.readSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => readRegularFile(stableReadWorkdir, stableReadPath, 16),
			/Protected (?:file|path) changed while it was being read/,
			"a canonical replacement after open must invalidate the descriptor snapshot",
		);
	} finally {
		mutableFs.readSync = renamedReadSync;
		syncBuiltinESMExports();
	}
	const fsyncMutationTarget = join(stableReadWorkdir, "fsync-mutation.txt");
	const originalFsyncSync = mutableFs.fsyncSync;
	let fsyncMutated = false;
	mutableFs.fsyncSync = ((fd: number) => {
		const result = originalFsyncSync(fd);
		if (!fsyncMutated) {
			fsyncMutated = true;
			originalWriteSync(fd, Buffer.from("evil!!!", "utf8"), 0, 7, 0);
		}
		return result;
	}) as typeof mutableFs.fsyncSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => atomicWriteRegularFile(stableReadWorkdir, fsyncMutationTarget, Buffer.from("trusted", "utf8"), { replace: false }),
			/temporary bytes changed before publication/,
		);
	} finally {
		mutableFs.fsyncSync = originalFsyncSync;
		syncBuiltinESMExports();
	}
	assert.equal(existsSync(fsyncMutationTarget), false);

	const rollbackCloseTarget = join(stableReadWorkdir, "rollback-close.txt");
	writeFileSync(rollbackCloseTarget, "authoritative-old", "utf8");
	const rollbackOpenSync = mutableFs.openSync;
	const rollbackRenameSync = mutableFs.renameSync;
	const rollbackCloseSync = mutableFs.closeSync;
	const rollbackTempFds = new Set<number>();
	let rollbackRenameInjected = false;
	let rollbackCloseInjected = false;
	mutableFs.openSync = ((filePath, flags, mode) => {
		const opened = rollbackOpenSync(filePath, flags, mode);
		const openedPath = String(filePath);
		if (
			openedPath.startsWith(stableReadWorkdir)
			&& openedPath.includes(".rollback-close.txt.write-")
			&& openedPath.endsWith("/content")
		) rollbackTempFds.add(opened);
		return opened;
	}) as typeof mutableFs.openSync;
	mutableFs.renameSync = ((oldPath, newPath) => {
		if (!rollbackRenameInjected && String(newPath) === rollbackCloseTarget) {
			rollbackRenameInjected = true;
			throw Object.assign(
				new Error("injected-publication-rename-failure"),
				{ code: "EIO" },
			);
		}
		return rollbackRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	mutableFs.closeSync = ((fd: number) => {
		const isRollbackTemp = rollbackTempFds.delete(fd);
		const result = rollbackCloseSync(fd);
		if (isRollbackTemp && !rollbackCloseInjected) {
			rollbackCloseInjected = true;
			throw Object.assign(
				new Error("injected-close-after-publication-failure"),
				{ code: "EIO" },
			);
		}
		return result;
	}) as typeof mutableFs.closeSync;
	syncBuiltinESMExports();
	let rollbackFailure: unknown;
	try {
		atomicWriteRegularFile(
			stableReadWorkdir,
			rollbackCloseTarget,
			Buffer.from("replacement", "utf8"),
		);
	} catch (error) {
		rollbackFailure = error;
	} finally {
		mutableFs.openSync = rollbackOpenSync;
		mutableFs.renameSync = rollbackRenameSync;
		mutableFs.closeSync = rollbackCloseSync;
		syncBuiltinESMExports();
	}
	assert.equal(rollbackRenameInjected, true);
	assert.equal(rollbackCloseInjected, true);
	assert(rollbackFailure instanceof AggregateError);
	assert.match(
		rollbackFailure.errors.map(String).join("\n"),
		/injected-publication-rename-failure[\s\S]*injected-close-after-publication-failure/,
	);
	assert.equal(
		readFileSync(rollbackCloseTarget, "utf8"),
		"authoritative-old",
		"cleanup failure must not remove the pre-existing target",
	);
	assert.deepEqual(
		readdirSync(stableReadWorkdir).filter(
			(name) => name.includes(".rollback-close.txt.write-"),
		),
		[],
		"failed publication and uncertain close must not strand a temp name",
	);

	const staticSymlinkSentinel = join(stableReadWorkdir, "static-special-sentinel.txt");
	const staticSymlinkTarget = join(stableReadWorkdir, "static-special-link.txt");
	writeFileSync(staticSymlinkSentinel, "sentinel", "utf8");
	symlinkSync(staticSymlinkSentinel, staticSymlinkTarget);
	assert.throws(
		() => atomicWriteRegularFile(
			stableReadWorkdir,
			staticSymlinkTarget,
			Buffer.from("replacement", "utf8"),
		),
		/symbolic link|not a regular file/i,
	);
	assert.equal(lstatSync(staticSymlinkTarget).isSymbolicLink(), true);
	assert.equal(readFileSync(staticSymlinkSentinel, "utf8"), "sentinel");

	const staticFifoTarget = join(stableReadWorkdir, "static-special-fifo.txt");
	execFileSync("mkfifo", [staticFifoTarget]);
	assert.throws(
		() => atomicWriteRegularFile(
			stableReadWorkdir,
			staticFifoTarget,
			Buffer.from("replacement", "utf8"),
		),
		/not a regular file/i,
	);
	assert.equal(lstatSync(staticFifoTarget).isFIFO(), true);

	const atomicReplaceTarget = join(stableReadWorkdir, "atomic-replace.txt");
	writeFileSync(atomicReplaceTarget, "old", "utf8");
	const atomicReplaceRenameSync = mutableFs.renameSync;
	const replacementObservations: string[] = [];
	let atomicReplacementRenames = 0;
	const observeReplacement = (): string => {
		try {
			return readFileSync(atomicReplaceTarget, "utf8");
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") return "absent";
			throw error;
		}
	};
	mutableFs.renameSync = ((oldPath, newPath) => {
		if (
			String(oldPath) === atomicReplaceTarget
			|| String(newPath) === atomicReplaceTarget
		) {
			atomicReplacementRenames++;
			replacementObservations.push(observeReplacement());
			const result = atomicReplaceRenameSync(oldPath, newPath);
			replacementObservations.push(observeReplacement());
			return result;
		}
		return atomicReplaceRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	try {
		atomicWriteRegularFile(
			stableReadWorkdir,
			atomicReplaceTarget,
			Buffer.from("new", "utf8"),
		);
	} finally {
		mutableFs.renameSync = atomicReplaceRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(atomicReplacementRenames, 1);
	assert.deepEqual(
		replacementObservations,
		["old", "new"],
		"cooperating lock-free readers must observe old or new, never absent/partial",
	);
	assert.equal(readFileSync(atomicReplaceTarget, "utf8"), "new");
	const { deriveGoalActivity } = await import(
		join(runtimeRoot, "extensions/goal-activity.ts")
	);
	const { GoalRuntime, CONTINUATION_IDLE_RETRY_MS } = await import(
		join(runtimeRoot, "extensions/goal-runtime.ts")
	);
	const goalEventsModule = (await import(
		join(runtimeRoot, "extensions/goal-events.ts")
	)) as Record<string, unknown>;
	const { DRAFT_ENTRY, rehydrateDraft } = await import(
		join(runtimeRoot, "extensions/goal-drafting.ts")
	);

	const unrelatedHistory = Array.from({ length: 50_000 }, (_, index) => ({
		type: "custom",
		customType: "unrelated-history",
		data: index,
	}));
	let branchReads = 0;
	const latestDraft = {
		type: "custom",
		customType: DRAFT_ENTRY,
		data: {
			version: 1,
			mode: "goal",
			seed: "bounded draft",
			startedAt: "draft-start",
			auditorEnabled: true,
		},
	};
	const draftLookupCalls: Array<{ customType: string; options: unknown }> = [];
	const draftCtx = {
		sessionManager: {
			getBranch() {
				branchReads++;
				return unrelatedHistory;
			},
			getLatestCustomEntry(customType: string, options: unknown) {
				draftLookupCalls.push({ customType, options });
				return latestDraft;
			},
		},
		ui: { notify() {} },
	};
	let draftingProfileInstalls = 0;
	let ordinaryProfileInstalls = 0;
	const draftCore = {
		tasksEnabled: true,
		installDraftingToolProfile() {
			draftingProfileInstalls++;
		},
		installGoalToolProfile() {
			ordinaryProfileInstalls++;
		},
	};
	rehydrateDraft(draftCore as never, draftCtx as never);
	assert.equal(
		branchReads,
		0,
		"draft rehydration must not materialize unrelated session history",
	);
	assert.deepEqual(draftLookupCalls, [
		{ customType: DRAFT_ENTRY, options: { scope: "active" } },
	]);
	assert.equal(draftingProfileInstalls, 1);
	assert.equal(ordinaryProfileInstalls, 0);

	let tombstoneDraftingInstalls = 0;
	let tombstoneOrdinaryInstalls = 0;
	const tombstoneCore = {
		tasksEnabled: true,
		installDraftingToolProfile() {
			tombstoneDraftingInstalls++;
		},
		installGoalToolProfile() {
			tombstoneOrdinaryInstalls++;
		},
	};
	const tombstoneCtx = {
		...draftCtx,
		sessionManager: {
			...draftCtx.sessionManager,
			getLatestCustomEntry() {
				return {
					...latestDraft,
					data: { ...latestDraft.data, clearedAt: "draft-cleared" },
				};
			},
		},
	};
	rehydrateDraft(tombstoneCore as never, tombstoneCtx as never);
	assert.equal(branchReads, 0);
	assert.equal(tombstoneDraftingInstalls, 0);
	assert.equal(
		tombstoneOrdinaryInstalls,
		1,
		"the latest draft tombstone must remain authoritative",
	);

	const noNewlineWorkdir = join(workdir, "ledger-no-newline");
	mkdirSync(join(noNewlineWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(
		join(noNewlineWorkdir, ".pi/goals/goal_events.jsonl"),
		JSON.stringify({
			type: "goal_created",
			goalId: "no-newline",
			objective: "one",
			sisyphus: false,
			autoContinue: false,
			at: "n-1",
		}),
		"utf8",
	);
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: noNewlineWorkdir },
			{ type: "goal_paused", goalId: "no-newline", reason: "two", at: "n-2" },
		),
		{ ok: true },
	);
	const noNewlineLedger = readGoalLedger({ cwd: noNewlineWorkdir });
	assert.equal(noNewlineLedger.malformed, 0);
	assert.equal(noNewlineLedger.validEvents, 2);

	const tornTailWorkdir = join(workdir, "ledger-torn-tail");
	mkdirSync(join(tornTailWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(
		join(tornTailWorkdir, ".pi/goals/goal_events.jsonl"),
		'{"type":"goal_created"',
		"utf8",
	);
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: tornTailWorkdir },
			{
				type: "goal_paused",
				goalId: "after-torn",
				reason: "survives",
				at: "torn-2",
			},
		),
		{ ok: true },
	);
	const tornTailLedger = readGoalLedger({ cwd: tornTailWorkdir });
	assert.equal(tornTailLedger.malformed, 1);
	assert.equal(tornTailLedger.validEvents, 1);
	assert.equal(tornTailLedger.events[0]?.type, "goal_paused");

	const abortedThenArchived = reconstructGoalLedger([
		{
			type: "goal_aborted",
			goalId: "archive-aborted",
			reason: "user",
			at: "abort-at",
		},
		{
			type: "goal_archived",
			goalId: "archive-aborted",
			archivePath: "archived.md",
			at: "archive-at",
		},
	]);
	assert.equal(
		abortedThenArchived.terminalGoals.get("archive-aborted")?.latestStatus,
		"aborted",
	);
	assert.equal(
		abortedThenArchived.terminalGoals.get("archive-aborted")?.abortedAt,
		"abort-at",
	);
	const archiveOnlySummary = buildCompactionSummary({
		goalsById: new Map(),
		focusedGoalId: null,
		ledgerEvents: [
			{
				type: "goal_archived",
				goalId: "archive-only",
				archivePath: "archive.md",
				at: "archive-only-at",
			},
		],
	});
	assert.match(archiveOnlySummary, /archive-only — archived/);
	assert.doesNotMatch(
		archiveOnlySummary,
		/archive-only — (?:completed|aborted)/,
	);
	assert.equal(
		deriveGoalActivity(
			[
				{
					type: "goal_archived",
					goalId: "archive-only",
					archivePath: "archive.md",
					at: "archive-only-at",
				},
			],
			"archive-only",
		)[0]?.text,
		"Archived the goal.",
	);

	const cacheWorkdir = join(workdir, "parse-cache-invalidation");
	const cachePath = join(cacheWorkdir, ".pi/goals/active_goal_cache.md");
	mkdirSync(join(cacheWorkdir, ".pi/goals"), { recursive: true });
	const cacheGoal = {
		id: "cache",
		objective: "first-value",
		status: "active" as const,
		autoContinue: false,
		usage: { tokensUsed: 0, activeSeconds: 0 },
		sisyphus: false,
		createdAt: "2026-08-18T00:00:00.000Z",
		updatedAt: "2026-08-18T00:00:00.000Z",
		activePath: ".pi/goals/active_goal_cache.md",
	};
	writeFileSync(cachePath, serializeGoalFile(cacheGoal), "utf8");
	assert.equal(parseGoalFile(cachePath)?.objective, "first-value");
	const cachedStat = statSync(cachePath);
	writeFileSync(
		cachePath,
		serializeGoalFile({ ...cacheGoal, objective: "other-value" }),
		"utf8",
	);
	mutableFs.lstatSync = ((filePath, options) =>
		String(filePath) === cachePath
			? cachedStat
			: originalLstatSync(
					filePath,
					options as never,
				)) as typeof mutableFs.lstatSync;
	syncBuiltinESMExports();
	try {
		assert.equal(
			parseGoalFile(cachePath)?.objective,
			"first-value",
			"the equal-size/equal-mtime setup must exercise the parse cache",
		);
		invalidateGoalPoolCache();
		assert.equal(parseGoalFile(cachePath)?.objective, "other-value");
	} finally {
		mutableFs.lstatSync = tracingLstatSync;
		syncBuiltinESMExports();
	}

	const snapshotWorkdir = join(workdir, "snapshot-removal");
	const snapshotActivePath =
		".pi/goals/active_goal_2026081800000000_snapshot.md";
	const snapshotAbsolutePath = join(snapshotWorkdir, snapshotActivePath);
	mkdirSync(join(snapshotWorkdir, ".pi/goals"), { recursive: true });
	const snapshotGoal = {
		...cacheGoal,
		id: "snapshot-real-id",
		objective: "snapshot removal",
		activePath: snapshotActivePath,
	};
	writeFileSync(snapshotAbsolutePath, serializeGoalFile(snapshotGoal), "utf8");
	const snapshotPath = join(snapshotWorkdir, ".pi/.goals-pool-snapshot.json");
	writeFileSync(
		snapshotPath,
		JSON.stringify({
			version: 1,
			dirMtimeMs: statSync(join(snapshotWorkdir, ".pi/goals")).mtimeMs,
			goals: [
				{ ...snapshotGoal, activePath: ".pi/goals/active_goal_other-path.md" },
				{ ...snapshotGoal, id: "other-id", activePath: snapshotActivePath },
				{
					...snapshotGoal,
					id: "keep-id",
					activePath: ".pi/goals/active_goal_keep.md",
				},
			],
		}),
		"utf8",
	);
	archiveCurrent({ cwd: snapshotWorkdir }, snapshotGoal);
	assert.equal(
		existsSync(snapshotPath),
		false,
		"archival must invalidate the derived snapshot instead of publishing a remove-only delta that could hide a successor",
	);
	invalidateGoalPoolCache();
	assert.equal(readActiveGoalPool({ cwd: snapshotWorkdir }).size, 0);

	const staleArchiveWorkdir = join(workdir, "ordinary-archive-stale-source");
	const staleArchiveRel = ".pi/goals/active_goal_2026081800000000_stale-archive.md";
	const staleArchivePath = join(staleArchiveWorkdir, staleArchiveRel);
	mkdirSync(join(staleArchiveWorkdir, ".pi/goals"), { recursive: true });
	const staleArchiveGoal = {
		...cacheGoal,
		id: "stale-archive",
		objective: "revision two",
		revision: 2,
		activePath: staleArchiveRel,
	};
	writeFileSync(staleArchivePath, serializeGoalFile(staleArchiveGoal), "utf8");
	const staleArchiveExpected = readGoalFileSnapshotChecked({ cwd: staleArchiveWorkdir }, staleArchivePath);
	const preEntrySuccessor = { ...staleArchiveGoal, objective: "revision ninety-nine", revision: 99 };
	writeFileSync(staleArchivePath, serializeGoalFile(preEntrySuccessor), "utf8");
	assert.throws(
		() => archiveGoalFile({ cwd: staleArchiveWorkdir }, staleArchiveGoal, staleArchiveExpected),
		/active file changed before archival/,
		"an archive caller must bind removal to the exact source snapshot captured under its lock",
	);
	assert.equal(parseGoalFile(staleArchivePath)?.revision, 99);
	assert.equal(existsSync(join(staleArchiveWorkdir, ".pi/goals/archived")), false);

	const ordinaryRaceWorkdir = join(workdir, "ordinary-archive-successor-race");
	const ordinaryRaceRel = ".pi/goals/active_goal_2026081800000000_ordinary-race.md";
	const ordinaryRacePath = join(ordinaryRaceWorkdir, ordinaryRaceRel);
	mkdirSync(join(ordinaryRaceWorkdir, ".pi/goals"), { recursive: true });
	const ordinaryRaceGoal = {
		...cacheGoal,
		id: "ordinary-race",
		objective: "original ordinary archive",
		activePath: ordinaryRaceRel,
	};
	const ordinarySuccessor = {
		...ordinaryRaceGoal,
		objective: "successor must survive",
		updatedAt: "2026-08-18T00:00:01.000Z",
	};
	writeFileSync(ordinaryRacePath, serializeGoalFile(ordinaryRaceGoal), "utf8");
	const ordinaryRaceOriginalIno = statSync(ordinaryRacePath).ino;
	const ordinaryArchiveRenameSync = mutableFs.renameSync;
	let ordinaryRaceInjected = false;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		const result = ordinaryArchiveRenameSync(oldPath, newPath);
		if (String(oldPath) === ordinaryRacePath && String(newPath).includes(".archive-")) {
			ordinaryRaceInjected = true;
			writeFileSync(ordinaryRacePath, serializeGoalFile(ordinarySuccessor), "utf8");
		}
		return result;
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let ordinaryArchived: ReturnType<typeof archiveGoalFile>;
	try {
		ordinaryArchived = archiveCurrent({ cwd: ordinaryRaceWorkdir }, ordinaryRaceGoal);
	} finally {
		mutableFs.renameSync = ordinaryArchiveRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(ordinaryRaceInjected, true);
	assert.notEqual(statSync(ordinaryRacePath).ino, ordinaryRaceOriginalIno);
	assert.equal(parseGoalFile(ordinaryRacePath)?.objective, "successor must survive");
	assert(ordinaryArchived.archivedPath);
	const ordinaryArchiveRecord = parseGoalFile(join(ordinaryRaceWorkdir, ordinaryArchived.archivedPath));
	assert.equal(ordinaryArchiveRecord?.objective, "original ordinary archive");
	assert.equal(ordinaryArchiveRecord?.activePath, undefined);
	assert.equal(ordinaryArchiveRecord?.archivedPath, ordinaryArchived.archivedPath);
	invalidateGoalPoolCache();
	assert.equal(readActiveGoalPool({ cwd: ordinaryRaceWorkdir }).get("ordinary-race")?.objective, "successor must survive");

	const preclaimRaceWorkdir = join(workdir, "ordinary-archive-preclaim-replacement");
	const preclaimRaceRel = ".pi/goals/active_goal_2026081800000000_preclaim-race.md";
	const preclaimRacePath = join(preclaimRaceWorkdir, preclaimRaceRel);
	mkdirSync(join(preclaimRaceWorkdir, ".pi/goals"), { recursive: true });
	const preclaimOriginal = {
		...cacheGoal,
		id: "preclaim-race",
		objective: "preclaim original",
		activePath: preclaimRaceRel,
	};
	const preclaimSuccessor = { ...preclaimOriginal, objective: "preclaim successor" };
	writeFileSync(preclaimRacePath, serializeGoalFile(preclaimOriginal), "utf8");
	const preclaimRenameSync = mutableFs.renameSync;
	let preclaimReplacements = 0;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		if (
			String(oldPath) === preclaimRacePath
			&& String(newPath).includes(".archive-")
			&& preclaimReplacements < 2
		) {
			const displaced = `${preclaimRacePath}.displaced-${preclaimReplacements}`;
			originalRenameSync(preclaimRacePath, displaced);
			writeFileSync(preclaimRacePath, serializeGoalFile(preclaimSuccessor), "utf8");
			unlinkSync(displaced);
			preclaimReplacements++;
		}
		return preclaimRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => archiveCurrent({ cwd: preclaimRaceWorkdir }, preclaimOriginal),
			/active file changed while being claimed/,
		);
		assert.equal(parseGoalFile(preclaimRacePath)?.objective, "preclaim successor");
		assert.throws(
			() => archiveCurrent({ cwd: preclaimRaceWorkdir }, preclaimSuccessor),
			/active file changed while being claimed/,
			"a repeated identical replacement must reuse one qualified archive identity",
		);
	} finally {
		mutableFs.renameSync = preclaimRenameSync;
		syncBuiltinESMExports();
	}
	const preclaimArchivedDir = join(preclaimRaceWorkdir, ".pi/goals/archived");
	assert.equal(
		readdirSync(preclaimArchivedDir).filter((name) => name.endsWith(".md")).length,
		2,
		"base plus one stable qualified archive is the fixed retry cardinality",
	);
	const preclaimArchived = archiveCurrent({ cwd: preclaimRaceWorkdir }, preclaimSuccessor);
	assert.match(preclaimArchived.archivedPath ?? "", /_[a-f0-9]{16}\.md$/);
	assert.equal(existsSync(preclaimRacePath), false);
	assert.equal(readdirSync(preclaimArchivedDir).filter((name) => name.endsWith(".md")).length, 2);
	const invalidUnlinkPath = join(
		snapshotWorkdir,
		".pi/goals/not-an-active-goal.txt",
	);
	writeFileSync(invalidUnlinkPath, "keep", "utf8");
	assert.throws(
		() =>
			safeUnlinkGoalFile(
				{ cwd: snapshotWorkdir },
				".pi/goals",
				".pi/goals/not-an-active-goal.txt",
				"keep-id",
			),
		/invalid active goal path/,
	);
	assert.equal(existsSync(invalidUnlinkPath), true);

	const exclusiveTempWorkdir = join(workdir, "exclusive-goal-temp");
	const exclusiveGoalRel = ".pi/goals/active_goal_exclusive.md";
	const exclusiveGoalPath = join(exclusiveTempWorkdir, exclusiveGoalRel);
	const exclusiveGoalSentinel = join(exclusiveTempWorkdir, "goal-temp-sentinel");
	mkdirSync(join(exclusiveTempWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(exclusiveGoalSentinel, "goal-temp-sentinel", "utf8");
	const predictableGoalTemp = `${exclusiveGoalPath}.${process.pid}.${Date.now()}.tmp`;
	symlinkSync(exclusiveGoalSentinel, predictableGoalTemp);
	atomicWriteGoalFile(
		{ cwd: exclusiveTempWorkdir },
		".pi/goals",
		exclusiveGoalRel,
		serializeGoalFile({ ...cacheGoal, id: "exclusive", activePath: exclusiveGoalRel }),
	);
	assert.equal(readFileSync(exclusiveGoalSentinel, "utf8"), "goal-temp-sentinel");
	assert.equal(lstatSync(predictableGoalTemp).isSymbolicLink(), true);
	assert.equal(parseGoalFile(exclusiveGoalPath)?.id, "exclusive");

	const exclusiveSnapshotPath = join(exclusiveTempWorkdir, ".pi/.goals-pool-snapshot.json");
	const exclusiveSnapshotSentinel = join(exclusiveTempWorkdir, "snapshot-temp-sentinel");
	writeFileSync(exclusiveSnapshotSentinel, "snapshot-temp-sentinel", "utf8");
	const predictableSnapshotTemp = `${exclusiveSnapshotPath}.${process.pid}.${Date.now()}.tmp`;
	symlinkSync(exclusiveSnapshotSentinel, predictableSnapshotTemp);
	refreshActiveGoalPoolSnapshot({ cwd: exclusiveTempWorkdir });
	assert.equal(readFileSync(exclusiveSnapshotSentinel, "utf8"), "snapshot-temp-sentinel");
	assert.equal(lstatSync(predictableSnapshotTemp).isSymbolicLink(), true);
	assert.equal(
		(JSON.parse(readFileSync(exclusiveSnapshotPath, "utf8")) as { version: number }).version,
		1,
	);

	const recoveryWorkdir = join(workdir, "completed-active-recovery");
	const recoveryActivePath =
		".pi/goals/active_goal_2026081800000000_recovery.md";
	const recoveryAbsolutePath = join(recoveryWorkdir, recoveryActivePath);
	mkdirSync(join(recoveryWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(
		recoveryAbsolutePath,
		serializeGoalFile({
			...cacheGoal,
			id: "recovery",
			objective: "recover a stranded completion",
			status: "complete",
			activePath: recoveryActivePath,
		}),
		"utf8",
	);
	const recoveryOriginalBytes = readFileSync(recoveryAbsolutePath);
	const recoveryOriginalIno = statSync(recoveryAbsolutePath).ino;
	const recoveryReport = runRecoveryReport({ cwd: recoveryWorkdir });
	assert.deepEqual(recoveryReport.completedActiveGoals, [
		{ goalId: "recovery", activePath: recoveryActivePath },
	]);
	const recoveryResult = await runRecoveryRepair(
		{ cwd: recoveryWorkdir },
		recoveryReport,
		async () => true,
	);
	assert.equal(recoveryResult.confirmed, true);
	assert.match(
		recoveryResult.applied.join("\n"),
		/archived recovered completed goal recovery/,
	);
	assert.equal(existsSync(recoveryAbsolutePath), false);
	assert(recoveryResult.backupDir);
	const recoveryPermanentBackup = join(
		recoveryResult.backupDir,
		"completed-recovery.md",
	);
	assert.equal(
		statSync(recoveryPermanentBackup).ino,
		recoveryOriginalIno,
		"successful recovery must retain the originally claimed inode as its permanent backup",
	);
	assert.deepEqual(readFileSync(recoveryPermanentBackup), recoveryOriginalBytes);
	const recoveryArchiveNames = readdirSync(
		join(recoveryWorkdir, ".pi/goals/archived"),
	);
	assert.equal(recoveryArchiveNames.length, 1);
	const [recoveryArchiveName] = recoveryArchiveNames;
	assert.ok(recoveryArchiveName);
	assert.equal(
		parseGoalFile(
			join(recoveryWorkdir, ".pi/goals/archived", recoveryArchiveName),
		)?.status,
		"complete",
	);
	assert.deepEqual(
		readGoalLedgerForGoal({ cwd: recoveryWorkdir }, "recovery").events.map(
			(event) => event.type,
		),
		["goal_completed", "goal_archived"],
	);
	assert.deepEqual(recoveryResult.failures, []);

	const recoveryLedgerFreshnessWorkdir = join(
		workdir,
		"recovery-ledger-freshness",
	);
	const recoveryLedgerFreshnessPath = join(
		recoveryLedgerFreshnessWorkdir,
		".pi/goals/goal_events.jsonl",
	);
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: recoveryLedgerFreshnessWorkdir },
			{
				type: "goal_created",
				goalId: "freshness",
				objective: "recovery must bypass warm ledger state",
				sisyphus: false,
				autoContinue: false,
				at: "freshness-created",
			},
		),
		{ ok: true },
	);
	assert.equal(
		readGoalLedger({ cwd: recoveryLedgerFreshnessWorkdir }).malformed,
		0,
	);
	mutableFs.appendFileSync(recoveryLedgerFreshnessPath, "not-json\n", "utf8");
	const recoveryLedgerFreshnessReport = runRecoveryReport({
		cwd: recoveryLedgerFreshnessWorkdir,
	});
	assert.equal(recoveryLedgerFreshnessReport.malformedLedgerLines, 1);
	assert.equal(recoveryLedgerFreshnessReport.healthy, false);
	ledgerIoProbe = {
		path: recoveryLedgerFreshnessPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
		failOpen: Object.assign(
			new Error("injected-recovery-ledger-open-failure"),
			{ code: "EIO" },
		),
	};
	try {
		assert.throws(
			() => runRecoveryReport({ cwd: recoveryLedgerFreshnessWorkdir }),
			/injected-recovery-ledger-open-failure/,
			"recovery reporting must surface an authoritative ledger open failure",
		);
	} finally {
		ledgerIoProbe = null;
	}

	const scanFailureWorkdir = join(workdir, "recovery-scan-failure");
	const scanFailureDir = join(scanFailureWorkdir, ".pi/goals");
	mkdirSync(scanFailureDir, { recursive: true });
	const recoveryOriginalReaddirSync = mutableFs.readdirSync;
	mutableFs.readdirSync = ((directory: import("node:fs").PathLike, options?: unknown) => {
		if (String(directory) === scanFailureDir) {
			throw Object.assign(new Error("injected-recovery-scan-failure"), { code: "EIO" });
		}
		return (recoveryOriginalReaddirSync as unknown as (directory: import("node:fs").PathLike, options?: unknown) => unknown)(directory, options);
	}) as typeof mutableFs.readdirSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => runRecoveryReport({ cwd: scanFailureWorkdir }),
			/injected-recovery-scan-failure/,
			"a non-ENOENT recovery scan failure must not report a healthy empty directory",
		);
	} finally {
		mutableFs.readdirSync = recoveryOriginalReaddirSync;
		syncBuiltinESMExports();
	}

	const snapshotScanFailureWorkdir = join(workdir, "recovery-snapshot-scan-failure");
	const snapshotScanFailurePath = join(
		snapshotScanFailureWorkdir,
		".pi/.goals-pool-snapshot.json",
	);
	mkdirSync(join(snapshotScanFailureWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(snapshotScanFailurePath, JSON.stringify({ goals: [] }), "utf8");
	const recoverySnapshotOriginalOpenSync = mutableFs.openSync;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		if (String(filePath) === snapshotScanFailurePath) {
			throw Object.assign(new Error("injected-recovery-snapshot-read-failure"), { code: "EIO" });
		}
		return recoverySnapshotOriginalOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => runRecoveryReport({ cwd: snapshotScanFailureWorkdir }),
			/injected-recovery-snapshot-read-failure/,
			"a non-ENOENT snapshot read failure must not be reported as healthy",
		);
	} finally {
		mutableFs.openSync = recoverySnapshotOriginalOpenSync;
		syncBuiltinESMExports();
	}

	const corruptSnapshotWorkdir = join(workdir, "recovery-corrupt-snapshot");
	const corruptSnapshotPath = join(
		corruptSnapshotWorkdir,
		".pi/.goals-pool-snapshot.json",
	);
	mkdirSync(join(corruptSnapshotWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(corruptSnapshotPath, "null", "utf8");
	assert.deepEqual(
		runRecoveryReport({ cwd: corruptSnapshotWorkdir }).orphanedSnapshotGoals,
		[],
		"a valid-JSON non-object derived snapshot must be ignored",
	);
	writeFileSync(
		corruptSnapshotPath,
		JSON.stringify({
			goals: [
				null,
				3,
				{
					id: "valid-orphan",
					activePath: ".pi/goals/active_goal_valid_orphan.md",
				},
			],
		}),
		"utf8",
	);
	assert.deepEqual(
		runRecoveryReport({ cwd: corruptSnapshotWorkdir }).orphanedSnapshotGoals,
		[
			{
				goalId: "valid-orphan",
				activePath: ".pi/goals/active_goal_valid_orphan.md",
			},
		],
		"invalid snapshot entries must not hide a later valid orphan",
	);

	const snapshotRepairFailureWorkdir = join(
		workdir,
		"recovery-snapshot-repair-failure",
	);
	const snapshotRepairFailureRoot = join(
		snapshotRepairFailureWorkdir,
		".pi/goals",
	);
	const snapshotRepairFailurePath = join(
		snapshotRepairFailureWorkdir,
		".pi/.goals-pool-snapshot.json",
	);
	mkdirSync(snapshotRepairFailureRoot, { recursive: true });
	writeFileSync(
		snapshotRepairFailurePath,
		JSON.stringify({
			version: 1,
			dirMtimeMs: statSync(snapshotRepairFailureRoot).mtimeMs,
			goals: [
				{
					...cacheGoal,
					id: "orphan",
					activePath: ".pi/goals/active_goal_missing.md",
				},
			],
		}),
		"utf8",
	);
	const snapshotRepairFailureReport = runRecoveryReport({
		cwd: snapshotRepairFailureWorkdir,
	});
	assert.equal(snapshotRepairFailureReport.orphanedSnapshotGoals.length, 1);
	const recoveryCurrentRenameSync = mutableFs.renameSync;
	let snapshotRepairPublicationInjected = false;
	mutableFs.renameSync = ((existingPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		if (String(newPath) === snapshotRepairFailurePath && !snapshotRepairPublicationInjected) {
			snapshotRepairPublicationInjected = true;
			throw Object.assign(
				new Error("injected-snapshot-refresh-publication-failure"),
				{ code: "EIO" },
			);
		}
		return recoveryCurrentRenameSync(existingPath, newPath);
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let snapshotRepairFailureResult: Awaited<
		ReturnType<typeof runRecoveryRepair>
	>;
	try {
		snapshotRepairFailureResult = await runRecoveryRepair(
			{ cwd: snapshotRepairFailureWorkdir },
			snapshotRepairFailureReport,
			async () => true,
		);
	} finally {
		mutableFs.renameSync = recoveryCurrentRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(snapshotRepairPublicationInjected, true);
	assert.deepEqual(snapshotRepairFailureResult.applied, []);
	assert.equal(
		snapshotRepairFailureResult.failures[0]?.operation,
		"refresh_pool_snapshot",
	);
	assert.equal(snapshotRepairFailureResult.failures[0]?.stage, "refresh");
	assert.match(
		snapshotRepairFailureResult.failures[0]?.message ?? "",
		/injected-snapshot-refresh-publication-failure/,
	);
	assert.deepEqual(
		(
			JSON.parse(readFileSync(snapshotRepairFailurePath, "utf8")) as {
				goals: Array<{ id: string }>;
			}
		).goals.map((goal) => goal.id),
		["orphan"],
		"a failed replacement must not be reported as a successful refresh",
	);
	assert.equal(
		readdirSync(join(snapshotRepairFailureWorkdir, ".pi")).some((name) =>
			name.endsWith(".tmp"),
		),
		false,
		"a failed snapshot replacement must clean up its temporary file",
	);

	const snapshotGoalReadFailureWorkdir = join(
		workdir,
		"recovery-snapshot-goal-read-failure",
	);
	const snapshotGoalReadFailureRoot = join(
		snapshotGoalReadFailureWorkdir,
		".pi/goals",
	);
	const snapshotGoalReadFailureActivePath =
		".pi/goals/active_goal_live.md";
	const snapshotGoalReadFailureAbsolutePath = join(
		snapshotGoalReadFailureWorkdir,
		snapshotGoalReadFailureActivePath,
	);
	const snapshotGoalReadFailurePath = join(
		snapshotGoalReadFailureWorkdir,
		".pi/.goals-pool-snapshot.json",
	);
	mkdirSync(snapshotGoalReadFailureRoot, { recursive: true });
	const snapshotGoalReadFailureGoal = {
		...cacheGoal,
		id: "live",
		activePath: snapshotGoalReadFailureActivePath,
	};
	writeFileSync(
		snapshotGoalReadFailureAbsolutePath,
		serializeGoalFile(snapshotGoalReadFailureGoal),
		"utf8",
	);
	writeFileSync(
		snapshotGoalReadFailurePath,
		JSON.stringify({
			version: 1,
			dirMtimeMs: statSync(snapshotGoalReadFailureRoot).mtimeMs,
			goals: [
				snapshotGoalReadFailureGoal,
				{
					...snapshotGoalReadFailureGoal,
					id: "orphan",
					activePath: ".pi/goals/active_goal_missing.md",
				},
			],
		}),
		"utf8",
	);
	const snapshotGoalReadFailureReport = runRecoveryReport({
		cwd: snapshotGoalReadFailureWorkdir,
	});
	assert.deepEqual(
		snapshotGoalReadFailureReport.orphanedSnapshotGoals.map(
			(goal) => goal.goalId,
		),
		["orphan"],
	);
	const recoveryGoalOriginalOpenSync = mutableFs.openSync;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		if (String(filePath) === snapshotGoalReadFailureAbsolutePath) {
			throw Object.assign(
				new Error("injected-recovery-goal-read-failure"),
				{ code: "EIO" },
			);
		}
		return recoveryGoalOriginalOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let snapshotGoalReadFailureResult: Awaited<
		ReturnType<typeof runRecoveryRepair>
	>;
	try {
		assert.throws(
			() => runRecoveryReport({ cwd: snapshotGoalReadFailureWorkdir }),
			/injected-recovery-goal-read-failure/,
			"recovery reporting must not relabel an active-file I/O error as malformed content",
		);
		snapshotGoalReadFailureResult = await runRecoveryRepair(
			{ cwd: snapshotGoalReadFailureWorkdir },
			snapshotGoalReadFailureReport,
			async () => true,
		);
	} finally {
		mutableFs.openSync = recoveryGoalOriginalOpenSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(snapshotGoalReadFailureResult.applied, []);
	assert.equal(
		snapshotGoalReadFailureResult.failures[0]?.operation,
		"refresh_pool_snapshot",
	);
	assert.equal(snapshotGoalReadFailureResult.failures[0]?.stage, "refresh");
	assert.match(
		snapshotGoalReadFailureResult.failures[0]?.message ?? "",
		/injected-recovery-goal-read-failure/,
	);
	assert.deepEqual(
		(
			JSON.parse(readFileSync(snapshotGoalReadFailurePath, "utf8")) as {
				goals: Array<{ id: string }>;
			}
		).goals.map((goal) => goal.id),
		["live", "orphan"],
		"an active-file read failure must preserve the prior snapshot",
	);

	const lockReadFailureWorkdir = join(workdir, "recovery-lock-read-failure");
	const lockReadFailureDir = join(lockReadFailureWorkdir, ".pi/goals/.locks");
	const lockReadFailurePath = join(lockReadFailureDir, "live.lock");
	mkdirSync(lockReadFailureDir, { recursive: true });
	writeFileSync(
		lockReadFailurePath,
		JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }),
		"utf8",
	);
	const recoveryLockReadOriginalOpenSync = mutableFs.openSync;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		if (String(filePath) === lockReadFailurePath) {
			throw Object.assign(new Error("injected-recovery-lock-read-failure"), {
				code: "EIO",
			});
		}
		return recoveryLockReadOriginalOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => runRecoveryReport({ cwd: lockReadFailureWorkdir }),
			/injected-recovery-lock-read-failure/,
			"a lock I/O error must not be reclassified as a stale unknown-owner lock",
		);
	} finally {
		mutableFs.openSync = recoveryLockReadOriginalOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(existsSync(lockReadFailurePath), true);

	const symlinkLockWorkdir = join(workdir, "recovery-symlink-lock");
	const symlinkLockDir = join(symlinkLockWorkdir, ".pi/goals/.locks");
	const symlinkLockTarget = join(workdir, "recovery-symlink-lock-target");
	mkdirSync(symlinkLockDir, { recursive: true });
	writeFileSync(symlinkLockTarget, JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }), "utf8");
	symlinkSync(symlinkLockTarget, join(symlinkLockDir, "linked.lock"));
	assert.throws(
		() => runRecoveryReport({ cwd: symlinkLockWorkdir }),
		/ELOOP|symbolic link|not a regular file/i,
		"recovery must never follow a final lock symlink",
	);
	assert.equal(existsSync(symlinkLockTarget), true);
	const symlinkLockDirWorkdir = join(workdir, "recovery-symlink-lock-directory");
	const externalEmptyLockDir = join(workdir, "recovery-external-empty-lock-directory");
	mkdirSync(join(symlinkLockDirWorkdir, ".pi/goals"), { recursive: true });
	mkdirSync(externalEmptyLockDir, { recursive: true });
	symlinkSync(externalEmptyLockDir, join(symlinkLockDirWorkdir, ".pi/goals/.locks"));
	assert.throws(
		() => runRecoveryReport({ cwd: symlinkLockDirWorkdir }),
		/symlink ancestor|non-directory/i,
		"an empty substituted lock namespace must not be reported healthy",
	);

	const fifoLockWorkdir = join(workdir, "recovery-fifo-lock");
	const fifoLockDir = join(fifoLockWorkdir, ".pi/goals/.locks");
	const fifoLockPath = join(fifoLockDir, "pipe.lock");
	mkdirSync(fifoLockDir, { recursive: true });
	execFileSync("mkfifo", [fifoLockPath]);
	const fifoProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { runRecoveryReport } from ${JSON.stringify(pathToFileURL(join(packageRoot, "extensions/goal-recovery.ts")).href)}; runRecoveryReport({ cwd: ${JSON.stringify(fifoLockWorkdir)} });`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual(
		(fifoProbe.error as NodeJS.ErrnoException | undefined)?.code,
		"ETIMEDOUT",
		"O_NONBLOCK must prevent a FIFO lock from hanging recovery",
	);
	assert.notEqual(fifoProbe.status, 0);
	assert.match(fifoProbe.stderr, /not a regular file/i);
	assert.equal(lstatSync(fifoLockPath).isFIFO(), true);

	const oversizedLockWorkdir = join(workdir, "recovery-oversized-lock");
	const oversizedLockDir = join(oversizedLockWorkdir, ".pi/goals/.locks");
	const oversizedLockPath = join(oversizedLockDir, "oversized.lock");
	mkdirSync(oversizedLockDir, { recursive: true });
	writeFileSync(oversizedLockPath, "x".repeat(MAX_GOAL_LOCK_BYTES + 1), "utf8");
	assert.throws(
		() => runRecoveryReport({ cwd: oversizedLockWorkdir }),
		/maximum is 16384/i,
		"recovery must reject an oversized lock before allocating or parsing it",
	);
	assert.equal(statSync(oversizedLockPath).size, MAX_GOAL_LOCK_BYTES + 1);

	const fifoGoalWorkdir = join(workdir, "recovery-fifo-active-goal");
	const fifoGoalPath = join(fifoGoalWorkdir, ".pi/goals/active_goal_pipe.md");
	mkdirSync(join(fifoGoalWorkdir, ".pi/goals"), { recursive: true });
	execFileSync("mkfifo", [fifoGoalPath]);
	const fifoGoalProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { runRecoveryReport } from ${JSON.stringify(pathToFileURL(join(packageRoot, "extensions/goal-recovery.ts")).href)}; runRecoveryReport({ cwd: ${JSON.stringify(fifoGoalWorkdir)} });`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual((fifoGoalProbe.error as NodeJS.ErrnoException | undefined)?.code, "ETIMEDOUT");
	assert.notEqual(fifoGoalProbe.status, 0);
	assert.match(fifoGoalProbe.stderr, /not a regular file/i);
	assert.equal(lstatSync(fifoGoalPath).isFIFO(), true);
	const fifoGoalPoolSyncProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { readActiveGoalPool } from ${JSON.stringify(pathToFileURL(join(runtimeRoot, "extensions/storage/goal-files.ts")).href)}; if (readActiveGoalPool({ cwd: ${JSON.stringify(fifoGoalWorkdir)} }).size !== 0) throw new Error("FIFO entered active pool");`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual(
		(fifoGoalPoolSyncProbe.error as NodeJS.ErrnoException | undefined)?.code,
		"ETIMEDOUT",
		"a normal synchronous pool read must not block on a FIFO goal",
	);
	assert.equal(fifoGoalPoolSyncProbe.status, 0, fifoGoalPoolSyncProbe.stderr);
	const fifoGoalPoolAsyncProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { readActiveGoalPoolAsync } from ${JSON.stringify(pathToFileURL(join(runtimeRoot, "extensions/storage/goal-files.ts")).href)}; if ((await readActiveGoalPoolAsync({ cwd: ${JSON.stringify(fifoGoalWorkdir)} })).size !== 0) throw new Error("FIFO entered async active pool");`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual(
		(fifoGoalPoolAsyncProbe.error as NodeJS.ErrnoException | undefined)?.code,
		"ETIMEDOUT",
		"session-start async rehydration must not block on a FIFO goal",
	);
	assert.equal(fifoGoalPoolAsyncProbe.status, 0, fifoGoalPoolAsyncProbe.stderr);
	assert.equal(lstatSync(fifoGoalPath).isFIFO(), true);

	const oversizedGoalWorkdir = join(workdir, "recovery-oversized-active-goal");
	const oversizedGoalPath = join(oversizedGoalWorkdir, ".pi/goals/active_goal_oversized.md");
	mkdirSync(join(oversizedGoalWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(oversizedGoalPath, Buffer.alloc(MAX_CHECKED_GOAL_FILE_BYTES + 1, 0x78));
	assert.throws(
		() => runRecoveryReport({ cwd: oversizedGoalWorkdir }),
		new RegExp(`maximum is ${MAX_CHECKED_GOAL_FILE_BYTES}`),
		"recovery must bound active-goal reads before allocation/parsing",
	);

	const fifoSnapshotWorkdir = join(workdir, "recovery-fifo-pool-snapshot");
	const fifoSnapshotPath = join(fifoSnapshotWorkdir, ".pi/.goals-pool-snapshot.json");
	mkdirSync(join(fifoSnapshotWorkdir, ".pi/goals"), { recursive: true });
	execFileSync("mkfifo", [fifoSnapshotPath]);
	const fifoSnapshotProbe = spawnSync(
		process.execPath,
		[
			"--experimental-transform-types",
			"--input-type=module",
			"--eval",
			`import { runRecoveryReport } from ${JSON.stringify(pathToFileURL(join(packageRoot, "extensions/goal-recovery.ts")).href)}; runRecoveryReport({ cwd: ${JSON.stringify(fifoSnapshotWorkdir)} });`,
		],
		{ encoding: "utf8", timeout: 3_000 },
	);
	assert.notEqual((fifoSnapshotProbe.error as NodeJS.ErrnoException | undefined)?.code, "ETIMEDOUT");
	assert.notEqual(fifoSnapshotProbe.status, 0);
	assert.match(fifoSnapshotProbe.stderr, /not a regular file/i);
	assert.equal(lstatSync(fifoSnapshotPath).isFIFO(), true);

	const oversizedSnapshotWorkdir = join(workdir, "recovery-oversized-pool-snapshot");
	const oversizedSnapshotPath = join(oversizedSnapshotWorkdir, ".pi/.goals-pool-snapshot.json");
	mkdirSync(join(oversizedSnapshotWorkdir, ".pi/goals"), { recursive: true });
	writeFileSync(oversizedSnapshotPath, Buffer.alloc(MAX_CHECKED_POOL_SNAPSHOT_BYTES + 1, 0x78));
	assert.throws(
		() => runRecoveryReport({ cwd: oversizedSnapshotWorkdir }),
		new RegExp(`maximum is ${MAX_CHECKED_POOL_SNAPSHOT_BYTES}`),
		"recovery must bound pool-snapshot reads before allocation/parsing",
	);

	const liveTtlWorkdir = join(workdir, "goal-lock-live-past-ttl");
	const liveTtlLock = acquireGoalLock(
		{ cwd: liveTtlWorkdir },
		"live-past-ttl",
		{ staleTtlMs: 1 },
	);
	const liveTtlPath = join(liveTtlWorkdir, ".pi/goals/.locks/live-past-ttl.lock");
	const liveTtlBytes = readFileSync(liveTtlPath);
	mock.timers.tick(31_000);
	assert.throws(
		() => acquireGoalLock(
			{ cwd: liveTtlWorkdir },
			"live-past-ttl",
			{ attempts: 2, retryMs: 0, staleTtlMs: 1 },
		),
		/Timed out acquiring the goal lock/,
		"elapsed TTL must never steal a lock from a live owner pid",
	);
	assert.deepEqual(readFileSync(liveTtlPath), liveTtlBytes);
	liveTtlLock.release();
	const liveTtlSuccessor = acquireGoalLock({ cwd: liveTtlWorkdir }, "live-past-ttl");
	liveTtlSuccessor.release();

	const lockCreationRaceWorkdir = join(workdir, "goal-lock-creation-replacement");
	const lockCreationRacePath = join(lockCreationRaceWorkdir, ".pi/goals/.locks/creation.lock");
	const lockCreationDisplacedPath = `${lockCreationRacePath}.displaced`;
	const lockCreationReplacement = Buffer.from(JSON.stringify({
		pid: process.pid,
		startedAt: new Date().toISOString(),
		token: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
	}), "utf8");
	const lockCreationLstatSync = mutableFs.lstatSync;
	let lockCreationTargetLstats = 0;
	mutableFs.lstatSync = ((filePath, options) => {
		if (String(filePath) === lockCreationRacePath && ++lockCreationTargetLstats === 2) {
			originalRenameSync(lockCreationRacePath, lockCreationDisplacedPath);
			writeFileSync(lockCreationRacePath, lockCreationReplacement);
		}
		return lockCreationLstatSync(filePath, options as never);
	}) as typeof mutableFs.lstatSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => acquireGoalLock({ cwd: lockCreationRaceWorkdir }, "creation"),
			/ownership path changed during creation/,
			"acquisition must not return ownership after its canonical lock inode is replaced",
		);
	} finally {
		mutableFs.lstatSync = lockCreationLstatSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(readFileSync(lockCreationRacePath), lockCreationReplacement);
	assert.equal(existsSync(lockCreationDisplacedPath), true);

	const gateCreationRaceWorkdir = join(workdir, "goal-gate-creation-replacement");
	const gateCreationRacePath = join(gateCreationRaceWorkdir, ".pi/goals/.locks/creation.lock.gate");
	const gateCreationDisplacedPath = `${gateCreationRacePath}.displaced`;
	const gateCreationReplacement = Buffer.from(JSON.stringify({
		pid: process.pid,
		startedAt: new Date().toISOString(),
		token: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
	}), "utf8");
	const gateCreationLstatSync = mutableFs.lstatSync;
	let gateCreationTargetLstats = 0;
	mutableFs.lstatSync = ((filePath, options) => {
		if (String(filePath) === gateCreationRacePath && ++gateCreationTargetLstats === 2) {
			originalRenameSync(gateCreationRacePath, gateCreationDisplacedPath);
			writeFileSync(gateCreationRacePath, gateCreationReplacement);
		}
		return gateCreationLstatSync(filePath, options as never);
	}) as typeof mutableFs.lstatSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => acquireGoalLock({ cwd: gateCreationRaceWorkdir }, "creation"),
			/ownership path changed during creation/,
			"gate acquisition must not return after its canonical ownership inode is replaced",
		);
	} finally {
		mutableFs.lstatSync = gateCreationLstatSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(readFileSync(gateCreationRacePath), gateCreationReplacement);
	assert.equal(existsSync(gateCreationDisplacedPath), true);

	const failedOpenValidationWorkdir = join(workdir, "goal-gate-open-validation-failure-cleanup");
	const failedOpenValidationPath = join(failedOpenValidationWorkdir, ".pi/goals/.locks/validation.lock.gate");
	const failedOpenValidationLstatSync = mutableFs.lstatSync;
	let failedOpenValidationInjected = false;
	mutableFs.lstatSync = ((filePath, options) => {
		if (String(filePath) === failedOpenValidationPath && !failedOpenValidationInjected) {
			failedOpenValidationInjected = true;
			throw Object.assign(new Error("injected-exclusive-open-validation-failure"), { code: "EIO" });
		}
		return failedOpenValidationLstatSync(filePath, options as never);
	}) as typeof mutableFs.lstatSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => acquireGoalLock({ cwd: failedOpenValidationWorkdir }, "validation"),
			/injected-exclusive-open-validation-failure/,
		);
	} finally {
		mutableFs.lstatSync = failedOpenValidationLstatSync;
		syncBuiltinESMExports();
	}
	assert.equal(failedOpenValidationInjected, true);
	assert.equal(
		existsSync(failedOpenValidationPath),
		false,
		"an O_EXCL inode must be removed when post-open path validation fails",
	);
	const afterFailedOpenValidation = acquireGoalLock(
		{ cwd: failedOpenValidationWorkdir },
		"validation",
	);
	afterFailedOpenValidation.release();

	const failedGateCreateWorkdir = join(workdir, "goal-gate-fsync-failure-cleanup");
	const failedGateCreatePath = join(failedGateCreateWorkdir, ".pi/goals/.locks/fsync.lock.gate");
	const failedGateCreateOpenSync = mutableFs.openSync;
	const failedGateCreateFsyncSync = mutableFs.fsyncSync;
	let failedGateCreateFd: number | null = null;
	let failedGateCreateInjected = false;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const fd = failedGateCreateOpenSync(filePath, flags, mode);
		if (String(filePath) === failedGateCreatePath) failedGateCreateFd = fd;
		return fd;
	}) as typeof mutableFs.openSync;
	mutableFs.fsyncSync = ((fd: number) => {
		failedGateCreateFsyncSync(fd);
		if (fd === failedGateCreateFd && !failedGateCreateInjected) {
			failedGateCreateInjected = true;
			throw Object.assign(new Error("injected-gate-fsync-failure"), { code: "EIO" });
		}
	}) as typeof mutableFs.fsyncSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => acquireGoalLock({ cwd: failedGateCreateWorkdir }, "fsync"),
			/injected-gate-fsync-failure/,
		);
	} finally {
		mutableFs.openSync = failedGateCreateOpenSync;
		mutableFs.fsyncSync = failedGateCreateFsyncSync;
		syncBuiltinESMExports();
	}
	assert.equal(failedGateCreateInjected, true);
	assert.equal(existsSync(failedGateCreatePath), false, "a failed exclusive gate creation must remove its exact inode");
	const afterFailedGateCreate = acquireGoalLock({ cwd: failedGateCreateWorkdir }, "fsync");
	afterFailedGateCreate.release();

	const failedMainCreateWorkdir = join(workdir, "goal-main-fsync-failure-cleanup");
	const failedMainCreatePath = join(failedMainCreateWorkdir, ".pi/goals/.locks/fsync.lock");
	const failedMainCreateGatePath = `${failedMainCreatePath}.gate`;
	const failedMainCreateOpenSync = mutableFs.openSync;
	const failedMainCreateFsyncSync = mutableFs.fsyncSync;
	let failedMainCreateFd: number | null = null;
	let failedMainCreateInjected = false;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const fd = failedMainCreateOpenSync(filePath, flags, mode);
		if (String(filePath) === failedMainCreatePath) failedMainCreateFd = fd;
		return fd;
	}) as typeof mutableFs.openSync;
	mutableFs.fsyncSync = ((fd: number) => {
		failedMainCreateFsyncSync(fd);
		if (fd === failedMainCreateFd && !failedMainCreateInjected) {
			failedMainCreateInjected = true;
			throw Object.assign(new Error("injected-main-fsync-failure"), { code: "EIO" });
		}
	}) as typeof mutableFs.fsyncSync;
	syncBuiltinESMExports();
	try {
		assert.throws(
			() => acquireGoalLock({ cwd: failedMainCreateWorkdir }, "fsync"),
			/injected-main-fsync-failure/,
		);
	} finally {
		mutableFs.openSync = failedMainCreateOpenSync;
		mutableFs.fsyncSync = failedMainCreateFsyncSync;
		syncBuiltinESMExports();
	}
	assert.equal(failedMainCreateInjected, true);
	assert.equal(
		existsSync(failedMainCreatePath),
		false,
		"a failed exclusive main-lock creation must remove its exact inode",
	);
	assert.equal(
		existsSync(failedMainCreateGatePath),
		false,
		"a main-lock creation failure must also release its gate",
	);
	const afterFailedMainCreate = acquireGoalLock({ cwd: failedMainCreateWorkdir }, "fsync");
	afterFailedMainCreate.release();

	const gateReleaseRetryWorkdir = join(workdir, "goal-gate-release-read-retry");
	const gateReleaseRetryPath = join(gateReleaseRetryWorkdir, ".pi/goals/.locks/retry.lock.gate");
	const gateReleaseRetryOpenSync = mutableFs.openSync;
	let gateReleaseRetryInjections = 0;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const readOnly = typeof flags === "number"
			&& (flags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (
			String(filePath) === gateReleaseRetryPath
			&& readOnly
			&& gateReleaseRetryInjections < 3
		) {
			gateReleaseRetryInjections++;
			throw Object.assign(new Error("injected-gate-release-read-failure"), { code: "EIO" });
		}
		return gateReleaseRetryOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let gateReleaseRetriedLock: ReturnType<typeof acquireGoalLock>;
	try {
		gateReleaseRetriedLock = acquireGoalLock({ cwd: gateReleaseRetryWorkdir }, "retry");
	} finally {
		mutableFs.openSync = gateReleaseRetryOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(gateReleaseRetryInjections, 3, "the mutation must exhaust the bounded initial gate-release retries");
	assert.equal(
		existsSync(gateReleaseRetryPath),
		true,
		"a committed owner must retain a gate whose release still needs retrying",
	);
	gateReleaseRetriedLock.release();
	assert.equal(existsSync(gateReleaseRetryPath), false, "the returned handle must retry its pending gate release");
	const afterGateReleaseRetry = acquireGoalLock({ cwd: gateReleaseRetryWorkdir }, "retry");
	afterGateReleaseRetry.release();

	const compoundGateFailureWorkdir = join(workdir, "goal-gate-compound-failure");
	const compoundGateFailureDir = join(compoundGateFailureWorkdir, ".pi/goals/.locks");
	const compoundGateFailureLockPath = join(compoundGateFailureDir, "compound.lock");
	const compoundGateFailurePath = `${compoundGateFailureLockPath}.gate`;
	mkdirSync(compoundGateFailureDir, { recursive: true });
	const compoundGateFailureLockBytes = Buffer.from(JSON.stringify({
		pid: -1,
		startedAt: "2000-01-01T00:00:00.000Z",
		token: "00000000-0000-4000-8000-000000000002",
	}), "utf8");
	writeFileSync(compoundGateFailureLockPath, compoundGateFailureLockBytes);
	const compoundGateFailureOpenSync = mutableFs.openSync;
	let compoundBackupFaults = 0;
	let compoundGateReleaseFaults = 0;
	let compoundBackupFailed = false;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const readOnly = typeof flags === "number"
			&& (flags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (compoundBackupFailed && String(filePath) === compoundGateFailurePath && readOnly) {
			compoundGateReleaseFaults++;
			throw Object.assign(new Error("injected-compound-gate-release-failure"), { code: "EIO" });
		}
		return compoundGateFailureOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let compoundFailure: unknown;
	try {
		recoverStaleGoalLock(
			{ cwd: compoundGateFailureWorkdir },
			"compound.lock",
			() => {
				compoundBackupFaults++;
				compoundBackupFailed = true;
				throw new Error("injected-compound-backup-failure");
			},
		);
	} catch (error) {
		compoundFailure = error;
	} finally {
		mutableFs.openSync = compoundGateFailureOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(compoundBackupFaults, 1, "the recovery-body mutation must fire once");
	assert.equal(
		compoundGateReleaseFaults,
		3,
		"the compound mutation must exhaust exactly the bounded gate-release attempts",
	);
	assert(compoundFailure instanceof AggregateError);
	assert.equal(compoundFailure.errors.length, 2);
	assert(compoundFailure.errors[0] instanceof GoalLockRecoveryError);
	assert.equal(compoundFailure.errors[0].stage, "backup");
	assert.match(String(compoundFailure.errors[0]), /injected-compound-backup-failure/);
	assert.match(String(compoundFailure.errors[1]), /injected-compound-gate-release-failure/);
	assert.equal(existsSync(compoundGateFailurePath), true, "persistent release failure must retain the ownership gate");
	assert.deepEqual(readFileSync(compoundGateFailureLockPath), compoundGateFailureLockBytes);
	// The mutation intentionally exhausts cooperative cleanup. With no Goal-X
	// writer active in this isolated fixture, emulate the documented offline repair.
	unlinkSync(compoundGateFailurePath);
	unlinkSync(compoundGateFailureLockPath);

	const reportedCompoundWorkdir = join(workdir, "goal-recovery-reported-compound-failure");
	const reportedCompoundDir = join(reportedCompoundWorkdir, ".pi/goals/.locks");
	const reportedCompoundLockPath = join(reportedCompoundDir, "reported.lock");
	const reportedCompoundGatePath = `${reportedCompoundLockPath}.gate`;
	mkdirSync(reportedCompoundDir, { recursive: true });
	writeFileSync(
		reportedCompoundLockPath,
		JSON.stringify({
			pid: -1,
			startedAt: "2000-01-01T00:00:00.000Z",
			token: "00000000-0000-4000-8000-000000000003",
		}),
		"utf8",
	);
	const reportedCompoundReport = runRecoveryReport({ cwd: reportedCompoundWorkdir });
	const reportedCompoundOpenSync = mutableFs.openSync;
	const reportedCompoundWriteFileSync = mutableFs.writeFileSync;
	let reportedCompoundBackupFaults = 0;
	let reportedCompoundReleaseFaults = 0;
	let reportedCompoundBackupFailed = false;
	mutableFs.writeFileSync = ((destination: import("node:fs").PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: unknown) => {
		if (String(destination).endsWith("lock-reported.lock")) {
			reportedCompoundBackupFaults++;
			reportedCompoundBackupFailed = true;
			throw Object.assign(new Error("injected-reported-backup-failure"), { code: "EIO" });
		}
		return (reportedCompoundWriteFileSync as unknown as (
			file: import("node:fs").PathOrFileDescriptor,
			body: string | NodeJS.ArrayBufferView,
			writeOptions?: unknown,
		) => void)(destination, data, options);
	}) as typeof mutableFs.writeFileSync;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const readOnly = typeof flags === "number"
			&& (flags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (reportedCompoundBackupFailed && String(filePath) === reportedCompoundGatePath && readOnly) {
			reportedCompoundReleaseFaults++;
			throw Object.assign(new Error("injected-reported-gate-release-failure"), { code: "EIO" });
		}
		return reportedCompoundOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let reportedCompoundResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		reportedCompoundResult = await runRecoveryRepair(
			{ cwd: reportedCompoundWorkdir },
			reportedCompoundReport,
			async () => true,
		);
	} finally {
		mutableFs.openSync = reportedCompoundOpenSync;
		mutableFs.writeFileSync = reportedCompoundWriteFileSync;
		syncBuiltinESMExports();
	}
	assert.equal(reportedCompoundBackupFaults, 1);
	assert.equal(reportedCompoundReleaseFaults, 3);
	assert.deepEqual(reportedCompoundResult.applied, []);
	assert.equal(reportedCompoundResult.failures[0]?.operation, "remove_stale_lock");
	assert.equal(reportedCompoundResult.failures[0]?.stage, "backup");
	assert.match(reportedCompoundResult.failures[0]?.message ?? "", /injected-reported-backup-failure/);
	assert.match(reportedCompoundResult.failures[0]?.message ?? "", /injected-reported-gate-release-failure/);
	assert.equal(existsSync(reportedCompoundLockPath), true);
	assert.equal(existsSync(reportedCompoundGatePath), true);
	unlinkSync(reportedCompoundGatePath);
	unlinkSync(reportedCompoundLockPath);

	const closeRetryWorkdir = join(workdir, "goal-main-close-retry");
	const closeRetryPath = join(closeRetryWorkdir, ".pi/goals/.locks/retry.lock");
	const closeRetryOpenSync = mutableFs.openSync;
	let closeRetryFd: number | null = null;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const fd = closeRetryOpenSync(filePath, flags, mode);
		if (String(filePath) === closeRetryPath) closeRetryFd = fd;
		return fd;
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let closeRetriedLock: ReturnType<typeof acquireGoalLock>;
	try {
		closeRetriedLock = acquireGoalLock({ cwd: closeRetryWorkdir }, "retry");
	} finally {
		mutableFs.openSync = closeRetryOpenSync;
		syncBuiltinESMExports();
	}
	assert.notEqual(closeRetryFd, null);
	const closeRetryCloseSync = mutableFs.closeSync;
	let closeRetryInjected = false;
	mutableFs.closeSync = ((fd: number) => {
		closeRetryCloseSync(fd);
		if (fd === closeRetryFd && !closeRetryInjected) {
			closeRetryInjected = true;
			throw Object.assign(new Error("injected-main-close-failure"), { code: "EIO" });
		}
	}) as typeof mutableFs.closeSync;
	syncBuiltinESMExports();
	try {
		closeRetriedLock.release();
	} finally {
		mutableFs.closeSync = closeRetryCloseSync;
		syncBuiltinESMExports();
	}
	assert.equal(closeRetryInjected, true);
	assert.equal(existsSync(closeRetryPath), false);
	const afterCloseRetry = acquireGoalLock({ cwd: closeRetryWorkdir }, "retry");
	afterCloseRetry.release();

	const abandonedGateWorkdir = join(workdir, "recovery-abandoned-lock-gate");
	const abandonedGateDir = join(abandonedGateWorkdir, ".pi/goals/.locks");
	const abandonedGatePath = join(abandonedGateDir, "abandoned.lock.gate");
	mkdirSync(abandonedGateDir, { recursive: true });
	const abandonedGateBytes = Buffer.from(
		JSON.stringify({
			pid: -1,
			startedAt: "2000-01-01T00:00:00.000Z",
			token: "00000000-0000-4000-8000-000000000000",
		}),
		"utf8",
	);
	writeFileSync(abandonedGatePath, abandonedGateBytes);
	assert.throws(
		() => acquireGoalLock(
			{ cwd: abandonedGateWorkdir },
			"abandoned",
			{ attempts: 2, retryMs: 0 },
		),
		/ownership gate/i,
		"an abandoned ownership gate must fail closed instead of recursively reaping itself",
	);
	assert.equal(existsSync(abandonedGatePath), true);
	const abandonedGateReport = runRecoveryReport({ cwd: abandonedGateWorkdir });
	assert.deepEqual(
		abandonedGateReport.abandonedGates.map(({ fileName, pid }) => ({ fileName, pid })),
		[{ fileName: "abandoned.lock.gate", pid: -1 }],
	);
	assert.equal(abandonedGateReport.healthy, false);
	const abandonedGateRepair = await runRecoveryRepair(
		{ cwd: abandonedGateWorkdir },
		abandonedGateReport,
		async () => true,
	);
	assert.deepEqual(abandonedGateRepair.applied, []);
	assert.equal(abandonedGateRepair.failures[0]?.operation, "remove_abandoned_gate");
	assert.equal(abandonedGateRepair.failures[0]?.stage, "offline_required");
	assert.match(abandonedGateRepair.failures[0]?.message ?? "", /cannot conditionally remove/i);
	assert.equal(existsSync(abandonedGatePath), true);
	assert.deepEqual(readFileSync(abandonedGatePath), abandonedGateBytes);
	assert(abandonedGateRepair.backupDir);
	unlinkSync(abandonedGatePath);
	const afterGateRepair = acquireGoalLock({ cwd: abandonedGateWorkdir }, "abandoned");
	afterGateRepair.release();

	const gatedReleaseWorkdir = join(workdir, "goal-lock-release-with-abandoned-gate");
	const gatedRelease = acquireGoalLock({ cwd: gatedReleaseWorkdir }, "release");
	const gatedReleaseDir = join(gatedReleaseWorkdir, ".pi/goals/.locks");
	const gatedReleasePath = join(gatedReleaseDir, "release.lock");
	const gatedReleaseGatePath = `${gatedReleasePath}.gate`;
	const gatedReleaseGateBytes = Buffer.from(JSON.stringify({
		pid: -1,
		startedAt: "2000-01-01T00:00:00.000Z",
		token: "00000000-0000-4000-8000-000000000001",
	}), "utf8");
	writeFileSync(gatedReleaseGatePath, gatedReleaseGateBytes);
	gatedRelease.release();
	assert.equal(existsSync(gatedReleasePath), false, "a live owner must release its lock even when the ownership gate is abandoned");
	assert.deepEqual(readFileSync(gatedReleaseGatePath), gatedReleaseGateBytes);
	gatedRelease.release();
	unlinkSync(gatedReleaseGatePath);

	const nullLockWorkdir = join(workdir, "recovery-null-lock");
	const nullLockDir = join(nullLockWorkdir, ".pi/goals/.locks");
	const nullLockPath = join(nullLockDir, "null.lock");
	mkdirSync(nullLockDir, { recursive: true });
	writeFileSync(nullLockPath, "null", "utf8");
	const nullLockReport = runRecoveryReport({ cwd: nullLockWorkdir });
	assert.deepEqual(
		nullLockReport.staleLocks.map(({ fileName, pid, startedAt }) => ({
			fileName,
			pid,
			startedAt,
		})),
		[{ fileName: "null.lock", pid: 0, startedAt: "" }],
	);
	const nullLockResult = await runRecoveryRepair(
		{ cwd: nullLockWorkdir },
		nullLockReport,
		async () => true,
	);
	assert.deepEqual(nullLockResult.failures, []);
	assert.match(nullLockResult.applied.join("\n"), /removed stale lock null\.lock/);
	assert.equal(existsSync(nullLockPath), false);

	const changedLockWorkdir = join(workdir, "recovery-changed-lock");
	const changedLockDir = join(changedLockWorkdir, ".pi/goals/.locks");
	const changedLockPath = join(changedLockDir, "changed.lock");
	mkdirSync(changedLockDir, { recursive: true });
	writeFileSync(
		changedLockPath,
		JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }),
		"utf8",
	);
	const changedLockReport = runRecoveryReport({ cwd: changedLockWorkdir });
	assert.equal(changedLockReport.staleLocks.length, 1);
	writeFileSync(
		changedLockPath,
		JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }),
		"utf8",
	);
	const changedLockResult = await runRecoveryRepair(
		{ cwd: changedLockWorkdir },
		changedLockReport,
		async () => true,
	);
	assert.deepEqual(changedLockResult.applied, []);
	assert.equal(changedLockResult.failures[0]?.operation, "remove_stale_lock");
	assert.equal(changedLockResult.failures[0]?.stage, "validate");
	assert.match(
		changedLockResult.failures[0]?.message ?? "",
		/lock is no longer stale/,
	);
	assert.equal(existsSync(changedLockPath), true);

	const racedLockWorkdir = join(workdir, "recovery-raced-lock");
	const racedLockDir = join(racedLockWorkdir, ".pi/goals/.locks");
	const racedLockPath = join(racedLockDir, "raced.lock");
	mkdirSync(racedLockDir, { recursive: true });
	writeFileSync(
		racedLockPath,
		JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }),
		"utf8",
	);
	const racedLockReport = runRecoveryReport({ cwd: racedLockWorkdir });
	assert.equal(racedLockReport.staleLocks.length, 1);
	const racedLockOriginalWriteFileSync = mutableFs.writeFileSync;
	mutableFs.writeFileSync = ((destination: import("node:fs").PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: unknown) => {
		if (String(destination).endsWith("lock-raced.lock")) {
			racedLockOriginalWriteFileSync(
				racedLockPath,
				JSON.stringify({
					pid: process.pid,
					startedAt: new Date().toISOString(),
				}),
				"utf8",
			);
		}
		return (racedLockOriginalWriteFileSync as unknown as (file: import("node:fs").PathOrFileDescriptor, data: string | NodeJS.ArrayBufferView, options?: unknown) => void)(destination, data, options);
	}) as typeof mutableFs.writeFileSync;
	syncBuiltinESMExports();
	let racedLockResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		racedLockResult = await runRecoveryRepair(
			{ cwd: racedLockWorkdir },
			racedLockReport,
			async () => true,
		);
	} finally {
		mutableFs.writeFileSync = racedLockOriginalWriteFileSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(racedLockResult.applied, []);
	assert.equal(racedLockResult.failures[0]?.operation, "remove_stale_lock");
	assert.equal(racedLockResult.failures[0]?.stage, "revalidate");
	assert.match(
		racedLockResult.failures[0]?.message ?? "",
		/lock changed while its recovery backup was being created/,
	);
	assert.equal(existsSync(racedLockPath), true);
	assert.equal(
		(JSON.parse(readFileSync(racedLockPath, "utf8")) as { pid: number }).pid,
		process.pid,
	);

	const staleLockFailureWorkdir = join(workdir, "recovery-stale-lock-failure");
	const staleLockFailureDir = join(staleLockFailureWorkdir, ".pi/goals/.locks");
	mkdirSync(staleLockFailureDir, { recursive: true });
	const staleLockFailurePath = join(staleLockFailureDir, "stale.lock");
	const staleLockFailureBytes = Buffer.from(
		JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }),
		"utf8",
	);
	writeFileSync(staleLockFailurePath, staleLockFailureBytes);
	const staleLockFailureReport = runRecoveryReport({ cwd: staleLockFailureWorkdir });
	const recoveryOriginalUnlinkSync = mutableFs.unlinkSync;
	mutableFs.unlinkSync = ((filePath: import("node:fs").PathLike) => {
		if (String(filePath).includes(".stale.lock.recovery-")) {
			throw Object.assign(new Error("injected-stale-lock-unlink-failure"), { code: "EACCES" });
		}
		return recoveryOriginalUnlinkSync(filePath);
	}) as typeof mutableFs.unlinkSync;
	syncBuiltinESMExports();
	let staleLockFailureResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		staleLockFailureResult = await runRecoveryRepair(
			{ cwd: staleLockFailureWorkdir },
			staleLockFailureReport,
			async () => true,
		);
	} finally {
		mutableFs.unlinkSync = recoveryOriginalUnlinkSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(staleLockFailureResult.applied, []);
	assert.equal(staleLockFailureResult.failures[0]?.operation, "remove_stale_lock");
	assert.equal(staleLockFailureResult.failures[0]?.stage, "unlink");
	assert.match(staleLockFailureResult.failures[0]?.message ?? "", /injected-stale-lock-unlink-failure/);
	assert(staleLockFailureResult.backupDir);
	assert.deepEqual(
		readFileSync(join(staleLockFailureResult.backupDir, "lock-stale.lock")),
		staleLockFailureBytes,
		"a failed quarantine deletion must retain the exact opened lock bytes in the permanent backup",
	);
	const staleQuarantineDir = readdirSync(staleLockFailureDir).find((name) =>
		name.startsWith(".stale.lock.recovery-"),
	);
	assert(staleQuarantineDir);
	assert.deepEqual(
		readFileSync(join(staleLockFailureDir, staleQuarantineDir, "stale.lock")),
		staleLockFailureBytes,
		"a failed deletion must leave the exact claimed inode in its private quarantine",
	);

	const successorRaceWorkdir = join(workdir, "recovery-lock-successor-race");
	const successorRaceDir = join(successorRaceWorkdir, ".pi/goals/.locks");
	const successorRacePath = join(successorRaceDir, "successor.lock");
	mkdirSync(successorRaceDir, { recursive: true });
	writeFileSync(
		successorRacePath,
		JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }),
		"utf8",
	);
	const successorRaceReport = runRecoveryReport({ cwd: successorRaceWorkdir });
	let successorHookActive = false;
	let successorAcquiredDuringRemoval = false;
	let successorBlockedByGate = false;
	const successorRaceOriginalRenameSync = mutableFs.renameSync;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		if (String(oldPath) === successorRacePath && !successorHookActive) {
			successorHookActive = true;
			try {
				acquireGoalLock({ cwd: successorRaceWorkdir }, "successor", { attempts: 2, retryMs: 0 });
				successorAcquiredDuringRemoval = true;
			} catch (error) {
				successorBlockedByGate = /ownership gate/i.test(error instanceof Error ? error.message : String(error));
			} finally {
				successorHookActive = false;
			}
		}
		return successorRaceOriginalRenameSync(oldPath, newPath);
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let successorRaceResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		successorRaceResult = await runRecoveryRepair(
			{ cwd: successorRaceWorkdir },
			successorRaceReport,
			async () => true,
		);
	} finally {
		mutableFs.renameSync = successorRaceOriginalRenameSync;
		syncBuiltinESMExports();
	}
	assert.deepEqual(successorRaceResult.failures, []);
	assert.equal(successorAcquiredDuringRemoval, false);
	assert.equal(successorBlockedByGate, true, "a new cooperative owner must not enter between stale-lock validation and unlink");
	const successorAfterRecovery = acquireGoalLock({ cwd: successorRaceWorkdir }, "successor");
	assert.equal(existsSync(successorRacePath), true);
	successorAfterRecovery.release();
	assert.equal(existsSync(successorRacePath), false);

	const seedCompletedRecovery = (cwd: string, goalId: string) => {
		const activePath = `.pi/goals/active_goal_2026081800000000_${goalId}.md`;
		const absolutePath = join(cwd, activePath);
		mkdirSync(join(cwd, ".pi/goals"), { recursive: true });
		writeFileSync(
			absolutePath,
			serializeGoalFile({
				...cacheGoal,
				id: goalId,
				objective: `recover ${goalId}`,
				status: "complete",
				activePath,
			}),
			"utf8",
		);
		return { activePath, absolutePath };
	};

	const lockFailureWorkdir = join(workdir, "recovery-lock-failure");
	seedCompletedRecovery(lockFailureWorkdir, "lock-failure");
	const lockFailureDir = join(lockFailureWorkdir, ".pi/goals/.locks");
	mkdirSync(lockFailureDir, { recursive: true });
	writeFileSync(
		join(lockFailureDir, "lock-failure.lock"),
		JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }),
		"utf8",
	);
	const lockFailureResult = await runRecoveryRepair(
		{ cwd: lockFailureWorkdir },
		runRecoveryReport({ cwd: lockFailureWorkdir }),
		async () => true,
	);
	assert.equal(lockFailureResult.failures[0]?.operation, "archive_completed_goal");
	assert.equal(lockFailureResult.failures[0]?.stage, "lock");
	assert.match(lockFailureResult.failures[0]?.message ?? "", /Timed out acquiring/);

	const copyFailureWorkdir = join(workdir, "recovery-copy-failure");
	const copyFailureGoal = seedCompletedRecovery(copyFailureWorkdir, "copy-failure");
	const copyFailureReport = runRecoveryReport({ cwd: copyFailureWorkdir });
	const recoveryOriginalLinkSync = mutableFs.linkSync;
	let recoveryCopyFailureInjected = false;
	mutableFs.linkSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		if (String(oldPath) === copyFailureGoal.absolutePath && String(newPath).endsWith("completed-copy-failure.md")) {
			recoveryCopyFailureInjected = true;
			throw Object.assign(new Error("injected-recovery-copy-failure"), { code: "EIO" });
		}
		return recoveryOriginalLinkSync(oldPath, newPath);
	}) as typeof mutableFs.linkSync;
	syncBuiltinESMExports();
	let copyFailureResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		copyFailureResult = await runRecoveryRepair(
			{ cwd: copyFailureWorkdir },
			copyFailureReport,
			async () => true,
		);
	} finally {
		mutableFs.linkSync = recoveryOriginalLinkSync;
		syncBuiltinESMExports();
	}
	assert.equal(recoveryCopyFailureInjected, true);
	assert.equal(copyFailureResult.failures[0]?.operation, "archive_completed_goal");
	assert.equal(copyFailureResult.failures[0]?.stage, "backup");
	assert.equal(existsSync(copyFailureGoal.absolutePath), true);

	const archiveFailureWorkdir = join(workdir, "recovery-archive-failure");
	const archiveFailureGoal = seedCompletedRecovery(archiveFailureWorkdir, "archive-failure");
	const archiveFailureReport = runRecoveryReport({ cwd: archiveFailureWorkdir });
	const archiveFailureOriginalLinkSync = mutableFs.linkSync;
	mutableFs.linkSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		if (String(newPath).includes("/.pi/goals/archived/") && String(newPath).includes("archive-failure")) {
			throw Object.assign(new Error("injected-recovery-archive-failure"), { code: "EIO" });
		}
		return archiveFailureOriginalLinkSync(oldPath, newPath);
	}) as typeof mutableFs.linkSync;
	syncBuiltinESMExports();
	let archiveFailureResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		archiveFailureResult = await runRecoveryRepair(
			{ cwd: archiveFailureWorkdir },
			archiveFailureReport,
			async () => true,
		);
	} finally {
		mutableFs.linkSync = archiveFailureOriginalLinkSync;
		syncBuiltinESMExports();
	}
	assert.equal(archiveFailureResult.failures[0]?.operation, "archive_completed_goal");
	assert.equal(archiveFailureResult.failures[0]?.stage, "archive");
	assert.equal(existsSync(archiveFailureGoal.absolutePath), true);

	const archiveCollisionWorkdir = join(workdir, "recovery-archive-collision");
	const archiveCollisionGoal = seedCompletedRecovery(archiveCollisionWorkdir, "archive-collision");
	const archiveCollisionRecord = parseGoalFile(archiveCollisionGoal.absolutePath);
	assert(archiveCollisionRecord);
	const archiveCollisionRel = archivedPathForGoal({ cwd: archiveCollisionWorkdir }, archiveCollisionRecord);
	const archiveCollisionPath = join(archiveCollisionWorkdir, archiveCollisionRel);
	const archiveCollisionSentinel = Buffer.from("pre-existing archive must survive", "utf8");
	mkdirSync(join(archiveCollisionWorkdir, ".pi/goals/archived"), { recursive: true });
	writeFileSync(archiveCollisionPath, archiveCollisionSentinel);
	const archiveCollisionResult = await runRecoveryRepair(
		{ cwd: archiveCollisionWorkdir },
		runRecoveryReport({ cwd: archiveCollisionWorkdir }),
		async () => true,
	);
	assert.deepEqual(archiveCollisionResult.applied, []);
	assert.equal(archiveCollisionResult.failures[0]?.operation, "archive_completed_goal");
	assert.equal(archiveCollisionResult.failures[0]?.stage, "archive");
	assert.match(archiveCollisionResult.failures[0]?.message ?? "", /EEXIST|exist/i);
	assert.deepEqual(readFileSync(archiveCollisionPath), archiveCollisionSentinel);
	assert.equal(existsSync(archiveCollisionGoal.absolutePath), true);
	assert(archiveCollisionResult.backupDir);
	assert.equal(
		statSync(join(archiveCollisionResult.backupDir, "completed-archive-collision.md")).ino,
		statSync(archiveCollisionGoal.absolutePath).ino,
		"a no-clobber archive failure must restore the claimed active inode while retaining its backup",
	);

	const identicalArchiveWorkdir = join(workdir, "recovery-identical-existing-archive");
	const identicalArchiveGoal = seedCompletedRecovery(identicalArchiveWorkdir, "identical-archive");
	const identicalArchiveRecord = parseGoalFile(identicalArchiveGoal.absolutePath);
	assert(identicalArchiveRecord);
	const identicalArchivedAt = new Date().toISOString();
	const identicalArchiveRel = archivedPathForGoal({ cwd: identicalArchiveWorkdir }, identicalArchiveRecord);
	const identicalArchivePath = join(identicalArchiveWorkdir, identicalArchiveRel);
	const identicalArchiveExpected = recoveredArchivedGoal(
		{ cwd: identicalArchiveWorkdir },
		identicalArchiveRecord,
		identicalArchivedAt,
		identicalArchiveRel,
	);
	mkdirSync(join(identicalArchiveWorkdir, ".pi/goals/archived"), { recursive: true });
	writeFileSync(identicalArchivePath, serializeGoalFile(identicalArchiveExpected), "utf8");
	const identicalArchiveBytes = readFileSync(identicalArchivePath);
	const identicalArchiveIno = statSync(identicalArchivePath).ino;
	const identicalArchiveResult = await runRecoveryRepair(
		{ cwd: identicalArchiveWorkdir },
		runRecoveryReport({ cwd: identicalArchiveWorkdir }),
		async () => true,
	);
	assert.deepEqual(identicalArchiveResult.failures, []);
	assert.match(identicalArchiveResult.applied.join("\n"), /archived recovered completed goal identical-archive/);
	assert.equal(existsSync(identicalArchiveGoal.absolutePath), false);
	assert.equal(statSync(identicalArchivePath).ino, identicalArchiveIno);
	assert.deepEqual(readFileSync(identicalArchivePath), identicalArchiveBytes);

	const activeRaceWorkdir = join(workdir, "recovery-active-inode-race");
	const activeRaceGoal = seedCompletedRecovery(activeRaceWorkdir, "active-race");
	const activeRaceReport = runRecoveryReport({ cwd: activeRaceWorkdir });
	const activeRaceBytes = readFileSync(activeRaceGoal.absolutePath);
	const activeRaceOriginalIno = statSync(activeRaceGoal.absolutePath).ino;
	const activeRaceOriginalRenameSync = mutableFs.renameSync;
	let activeRaceInjected = false;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		const result = activeRaceOriginalRenameSync(oldPath, newPath);
		if (
			String(oldPath) === activeRaceGoal.absolutePath
			&& String(newPath).includes(".recovery-backup-")
		) {
			activeRaceInjected = true;
			writeFileSync(activeRaceGoal.absolutePath, activeRaceBytes);
		}
		return result;
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let activeRaceResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		activeRaceResult = await runRecoveryRepair(
			{ cwd: activeRaceWorkdir },
			activeRaceReport,
			async () => true,
		);
	} finally {
		mutableFs.renameSync = activeRaceOriginalRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(activeRaceInjected, true);
	assert.deepEqual(activeRaceResult.applied, []);
	assert.equal(activeRaceResult.failures[0]?.operation, "archive_completed_goal");
	assert.equal(activeRaceResult.failures[0]?.stage, "archive");
	assert.match(activeRaceResult.failures[0]?.message ?? "", /successor appeared/i);
	assert.notEqual(statSync(activeRaceGoal.absolutePath).ino, activeRaceOriginalIno);
	assert.deepEqual(readFileSync(activeRaceGoal.absolutePath), activeRaceBytes);
	assert(activeRaceResult.backupDir);
	const activeRaceBackup = join(activeRaceResult.backupDir, "completed-active-race.md");
	assert.equal(statSync(activeRaceBackup).ino, activeRaceOriginalIno);
	assert.deepEqual(readFileSync(activeRaceBackup), activeRaceBytes);

	const lateSuccessorWorkdir = join(workdir, "recovery-late-active-successor");
	const lateSuccessorGoal = seedCompletedRecovery(lateSuccessorWorkdir, "late-successor");
	refreshActiveGoalPoolSnapshot({ cwd: lateSuccessorWorkdir });
	const lateSuccessorReport = runRecoveryReport({ cwd: lateSuccessorWorkdir });
	const lateSuccessorRecord = parseGoalFile(lateSuccessorGoal.absolutePath);
	assert(lateSuccessorRecord);
	const lateSuccessor = {
		...lateSuccessorRecord,
		objective: "late successor remains authoritative",
		status: "active" as const,
		updatedAt: "2026-08-18T00:00:02.000Z",
	};
	const lateSuccessorSnapshotPath = join(lateSuccessorWorkdir, ".pi/.goals-pool-snapshot.json");
	const lateSuccessorUnlinkSync = mutableFs.unlinkSync;
	let lateSuccessorInjected = false;
	mutableFs.unlinkSync = ((filePath: import("node:fs").PathLike) => {
		if (!lateSuccessorInjected && String(filePath) === lateSuccessorSnapshotPath) {
			lateSuccessorInjected = true;
			writeFileSync(lateSuccessorGoal.absolutePath, serializeGoalFile(lateSuccessor), "utf8");
			throw Object.assign(new Error("injected-snapshot-unlink-failure"), { code: "EIO" });
		}
		return lateSuccessorUnlinkSync(filePath);
	}) as typeof mutableFs.unlinkSync;
	syncBuiltinESMExports();
	let lateSuccessorResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		lateSuccessorResult = await runRecoveryRepair(
			{ cwd: lateSuccessorWorkdir },
			lateSuccessorReport,
			async () => true,
		);
	} finally {
		mutableFs.unlinkSync = lateSuccessorUnlinkSync;
		syncBuiltinESMExports();
	}
	assert.equal(lateSuccessorInjected, true);
	assert.deepEqual(lateSuccessorResult.failures, []);
	assert.equal(existsSync(lateSuccessorSnapshotPath), true, "the injected cleanup failure must preserve the stale snapshot fixture");
	assert.equal(parseGoalFile(lateSuccessorGoal.absolutePath)?.objective, "late successor remains authoritative");
	invalidateGoalPoolCache();
	assert.equal(
		readActiveGoalPool({ cwd: lateSuccessorWorkdir }).get("late-successor")?.objective,
		"late successor remains authoritative",
		"derived snapshot cleanup must not hide a successor created after archival",
	);

	const timestampWorkdir = join(workdir, "recovery-completion-timestamp");
	const timestampGoal = seedCompletedRecovery(timestampWorkdir, "timestamp");
	const timestampRecord = parseGoalFile(timestampGoal.absolutePath);
	assert(timestampRecord);
	const originalCompletionAt = "2001-02-03T04:05:06.000Z";
	writeFileSync(
		timestampGoal.absolutePath,
		serializeGoalFile({ ...timestampRecord, updatedAt: originalCompletionAt }),
		"utf8",
	);
	const timestampResult = await runRecoveryRepair(
		{ cwd: timestampWorkdir },
		runRecoveryReport({ cwd: timestampWorkdir }),
		async () => true,
	);
	assert.deepEqual(timestampResult.failures, []);
	invalidateGoalLedgerCache();
	const timestampLedger = readGoalLedgerForGoal({ cwd: timestampWorkdir }, "timestamp", { maxEvents: 8 });
	const timestampCompletions = timestampLedger.events.filter((event) => event.type === "goal_completed");
	assert.equal(timestampCompletions.length, 1);
	assert.equal(timestampCompletions[0]?.at, originalCompletionAt);

	const invalidTimestampWorkdir = join(workdir, "recovery-invalid-timestamp-stable-path");
	const invalidTimestampGoal = seedCompletedRecovery(invalidTimestampWorkdir, "invalid-timestamp");
	const invalidTimestampRecord = parseGoalFile(invalidTimestampGoal.absolutePath);
	assert(invalidTimestampRecord);
	writeFileSync(
		invalidTimestampGoal.absolutePath,
		serializeGoalFile({ ...invalidTimestampRecord, updatedAt: "not-a-timestamp" }),
		"utf8",
	);
	const invalidTimestampReport = runRecoveryReport({ cwd: invalidTimestampWorkdir });
	const invalidTimestampRenameSync = mutableFs.renameSync;
	let advancedDuringInvalidTimestampClaim = false;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		const result = invalidTimestampRenameSync(oldPath, newPath);
		if (
			String(oldPath) === invalidTimestampGoal.absolutePath
			&& String(newPath).includes(".recovery-backup-")
		) {
			advancedDuringInvalidTimestampClaim = true;
			mock.timers.tick(35);
		}
		return result;
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let invalidTimestampResult: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		invalidTimestampResult = await runRecoveryRepair(
			{ cwd: invalidTimestampWorkdir },
			invalidTimestampReport,
			async () => true,
		);
	} finally {
		mutableFs.renameSync = invalidTimestampRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(advancedDuringInvalidTimestampClaim, true);
	assert.deepEqual(invalidTimestampResult.failures, []);
	const invalidTimestampArchives = readdirSync(join(invalidTimestampWorkdir, ".pi/goals/archived"));
	assert.equal(invalidTimestampArchives.length, 1);
	invalidateGoalLedgerCache();
	const invalidTimestampFacts = readGoalLedgerForGoal({ cwd: invalidTimestampWorkdir }, "invalid-timestamp", { maxEvents: 8 });
	const invalidTimestampArchivePath = `.pi/goals/archived/${invalidTimestampArchives[0]}`;
	assert.equal(invalidTimestampFacts.events.find((event) => event.type === "goal_archived")?.archivePath, invalidTimestampArchivePath);

	const noDuplicateWorkdir = join(workdir, "recovery-no-duplicate-completion");
	seedCompletedRecovery(noDuplicateWorkdir, "no-duplicate");
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: noDuplicateWorkdir },
			{ type: "goal_completed", goalId: "no-duplicate", at: "already-completed" },
		),
		{ ok: true },
	);
	const noDuplicateResult = await runRecoveryRepair(
		{ cwd: noDuplicateWorkdir },
		runRecoveryReport({ cwd: noDuplicateWorkdir }),
		async () => true,
	);
	assert.deepEqual(noDuplicateResult.failures, []);
	invalidateGoalLedgerCache();
	const noDuplicateLedger = readGoalLedgerForGoal({ cwd: noDuplicateWorkdir }, "no-duplicate", { maxEvents: 8 });
	assert.equal(noDuplicateLedger.events.filter((event) => event.type === "goal_completed").length, 1);
	assert.equal(noDuplicateLedger.events.filter((event) => event.type === "goal_archived").length, 1);

	const wrongArchiveEventWorkdir = join(workdir, "recovery-wrong-archive-event-path");
	seedCompletedRecovery(wrongArchiveEventWorkdir, "wrong-archive-event");
	assert.deepEqual(
		appendGoalEvent(
			{ cwd: wrongArchiveEventWorkdir },
			{
				type: "goal_archived",
				goalId: "wrong-archive-event",
				archivePath: ".pi/goals/archived/wrong.md",
				at: "already-archived-wrongly",
			},
		),
		{ ok: true },
	);
	const wrongArchiveEventResult = await runRecoveryRepair(
		{ cwd: wrongArchiveEventWorkdir },
		runRecoveryReport({ cwd: wrongArchiveEventWorkdir }),
		async () => true,
	);
	assert.deepEqual(wrongArchiveEventResult.failures, []);
	const wrongArchiveFiles = readdirSync(join(wrongArchiveEventWorkdir, ".pi/goals/archived"));
	assert.equal(wrongArchiveFiles.length, 1);
	const actualWrongArchivePath = `.pi/goals/archived/${wrongArchiveFiles[0]}`;
	invalidateGoalLedgerCache();
	const wrongArchiveFacts = readGoalLedgerForGoal({ cwd: wrongArchiveEventWorkdir }, "wrong-archive-event", { maxEvents: 8 });
	assert.equal(
		wrongArchiveFacts.events.filter((event) => event.type === "goal_archived").length,
		2,
		"a wrong-path historical archive event must not suppress the actual archive event",
	);
	assert.equal(wrongArchiveFacts.archivedArchivePath, actualWrongArchivePath);

	const claimCrashWorkdir = join(workdir, "recovery-crash-after-claim");
	const claimCrashGoal = seedCompletedRecovery(claimCrashWorkdir, "claim-crash");
	const claimCrashReport = runRecoveryReport({ cwd: claimCrashWorkdir });
	const claimCrashRenameSync = mutableFs.renameSync;
	let claimCrashInjected = false;
	mutableFs.renameSync = ((oldPath: import("node:fs").PathLike, newPath: import("node:fs").PathLike) => {
		const result = claimCrashRenameSync(oldPath, newPath);
		if (
			!claimCrashInjected
			&& String(oldPath) === claimCrashGoal.absolutePath
			&& String(newPath).includes(".recovery-backup-")
		) {
			claimCrashInjected = true;
			throw new Error("injected-process-death-after-recovery-claim");
		}
		return result;
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let claimCrashFirst: Awaited<ReturnType<typeof runRecoveryRepair>>;
	try {
		claimCrashFirst = await runRecoveryRepair(
			{ cwd: claimCrashWorkdir },
			claimCrashReport,
			async () => true,
		);
	} finally {
		mutableFs.renameSync = claimCrashRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(claimCrashInjected, true);
	assert.equal(claimCrashFirst.failures[0]?.operation, "archive_completed_goal");
	assert.equal(claimCrashFirst.failures[0]?.stage, "backup");
	assert.equal(existsSync(claimCrashGoal.absolutePath), false);
	const claimCrashPending = runRecoveryReport({ cwd: claimCrashWorkdir });
	assert.deepEqual(claimCrashPending.completedActiveGoals, []);
	assert.equal(claimCrashPending.pendingRecoveryLedger[0]?.goalId, "claim-crash");
	const claimCrashBackup = join(
		claimCrashWorkdir,
		claimCrashPending.pendingRecoveryLedger[0]?.backupPath ?? "missing",
	);
	const claimCrashBackupBytes = readFileSync(claimCrashBackup);
	const claimCrashRetry = await runRecoveryRepair(
		{ cwd: claimCrashWorkdir },
		claimCrashPending,
		async () => true,
	);
	assert.deepEqual(claimCrashRetry.failures, []);
	assert.match(claimCrashRetry.applied.join("\n"), /archived recovered completed goal claim-crash/);
	assert.match(claimCrashRetry.applied.join("\n"), /reconciled recovery ledger for claim-crash/);
	assert.deepEqual(readFileSync(claimCrashBackup), claimCrashBackupBytes, "marker-bound recovery backup remains permanent");
	assert.equal(runRecoveryReport({ cwd: claimCrashWorkdir }).healthy, true);

	const ledgerFailureWorkdir = join(workdir, "recovery-ledger-failure");
	const ledgerFailureGoal = seedCompletedRecovery(ledgerFailureWorkdir, "ledger-failure");
	symlinkSync("goal_events.jsonl", join(ledgerFailureWorkdir, ".pi/goals/goal_events.jsonl"));
	const ledgerFailureResult = await runRecoveryRepair(
		{ cwd: ledgerFailureWorkdir },
		{
			scannedAt: new Date().toISOString(),
			malformedGoalFiles: [],
			malformedLedgerLines: 0,
			staleLocks: [],
			abandonedGates: [],
			orphanedSnapshotGoals: [],
			completedActiveGoals: [{ goalId: "ledger-failure", activePath: ledgerFailureGoal.activePath }],
			pendingRecoveryLedger: [],
			healthy: false,
		},
		async () => true,
	);
	assert.match(ledgerFailureResult.applied.join("\n"), /archived recovered completed goal ledger-failure/);
	assert.equal(ledgerFailureResult.failures[0]?.operation, "append_recovery_ledger");
	assert.match(ledgerFailureResult.failures[0]?.message ?? "", /ELOOP|symbolic link|not a regular file/i);
	const ledgerFailurePendingDir = join(ledgerFailureWorkdir, ".pi/goals/.recovery-ledger-pending");
	assert.equal(readdirSync(ledgerFailurePendingDir).filter((name) => name.endsWith(".json")).length, 1);
	unlinkSync(join(ledgerFailureWorkdir, ".pi/goals/goal_events.jsonl"));
	const ledgerCorruptReport = runRecoveryReport({ cwd: ledgerFailureWorkdir });
	const ledgerCorruptEntry = ledgerCorruptReport.pendingRecoveryLedger[0];
	assert(ledgerCorruptEntry);
	const ledgerCorruptArchivePath = join(ledgerFailureWorkdir, ledgerCorruptEntry.archivePath);
	const ledgerCorruptArchiveBytes = readFileSync(ledgerCorruptArchivePath);
	const ledgerCorruptArchive = parseGoalFile(ledgerCorruptArchivePath);
	assert(ledgerCorruptArchive);
	writeFileSync(
		ledgerCorruptArchivePath,
		serializeGoalFile({ ...ledgerCorruptArchive, objective: "valid but unrelated archive bytes" }),
		"utf8",
	);
	const ledgerCorruptResult = await runRecoveryRepair(
		{ cwd: ledgerFailureWorkdir },
		ledgerCorruptReport,
		async () => true,
	);
	assert.equal(ledgerCorruptResult.failures[0]?.operation, "append_recovery_ledger");
	assert.equal(ledgerCorruptResult.failures[0]?.stage, "read");
	assert.match(ledgerCorruptResult.failures[0]?.message ?? "", /no matching archived goal/);
	assert.equal(readdirSync(ledgerFailurePendingDir).filter((name) => name.endsWith(".json")).length, 1);
	writeFileSync(ledgerCorruptArchivePath, ledgerCorruptArchiveBytes);
	const ledgerRetryReport = runRecoveryReport({ cwd: ledgerFailureWorkdir });
	assert.deepEqual(ledgerRetryReport.completedActiveGoals, []);
	assert.deepEqual(
		ledgerRetryReport.pendingRecoveryLedger.map((entry) => entry.goalId),
		["ledger-failure"],
		"a post-archive ledger failure must remain discoverable without an active goal",
	);
	const ledgerRetryResult = await runRecoveryRepair(
		{ cwd: ledgerFailureWorkdir },
		ledgerRetryReport,
		async () => true,
	);
	assert.deepEqual(ledgerRetryResult.failures, []);
	assert.match(ledgerRetryResult.applied.join("\n"), /reconciled recovery ledger for ledger-failure/);
	assert.equal(readdirSync(ledgerFailurePendingDir).filter((name) => name.endsWith(".json")).length, 0);
	invalidateGoalLedgerCache();
	const ledgerRetryFacts = readGoalLedgerForGoal({ cwd: ledgerFailureWorkdir }, "ledger-failure", { maxEvents: 8 });
	assert.equal(ledgerRetryFacts.events.filter((event) => event.type === "goal_completed").length, 1);
	assert.equal(ledgerRetryFacts.events.filter((event) => event.type === "goal_archived").length, 1);

	function createHarness(
		label: string,
		options: {
			autoContinue?: boolean;
			confirm?: () => boolean | Promise<boolean>;
			goal?: Partial<{
				autoContinue: boolean;
				objective: string;
				skipAuditor: boolean;
				status: "active" | "paused" | "blocked" | "budget_limited";
				tokenBudget: number;
				usage: { tokensUsed: number; activeSeconds: number };
			}>;
			hasUI?: boolean;
			isIdle?: boolean;
			runCompletionAuditor?: (...args: unknown[]) => Promise<unknown>;
			skipAuditor?: boolean;
			withTasks?: boolean;
		} = {},
	) {
		const cwd = join(workdir, label);
		const activePath = ".pi/goals/active_goal_2026080612000000_target.md";
		const absoluteActivePath = join(cwd, activePath);
		mkdirSync(join(cwd, ".pi/goals"), { recursive: true });
		const timestamp = new Date(Date.now()).toISOString();
		const goal = {
			id: "target",
			objective:
				options.goal?.objective ?? "exercise bounded accounting persistence",
			status: options.goal?.status ?? "active",
			autoContinue: options.goal?.autoContinue ?? options.autoContinue ?? false,
			skipAuditor:
				options.goal?.skipAuditor ??
				(options.skipAuditor === true ? true : undefined),
			usage: options.goal?.usage ?? { tokensUsed: 0, activeSeconds: 0 },
			sisyphus: false,
			createdAt: timestamp,
			updatedAt: timestamp,
			activePath,
			...(options.goal?.tokenBudget !== undefined
				? { tokenBudget: options.goal.tokenBudget }
				: {}),
			...(options.withTasks
				? {
						taskList: {
							tasks: [
								{ id: "task-a", title: "Task A", status: "pending" as const },
								{ id: "task-b", title: "Task B", status: "pending" as const },
							],
							blockCompletion: true,
							proposedAt: timestamp,
						},
					}
				: {}),
		};
		writeFileSync(
			absoluteActivePath,
			`${JSON.stringify(goal, null, 2)}\n\n# Goal Prompt\n\n${goal.objective}\n\n## Progress\n`,
			"utf8",
		);

		const trace: RuntimeTrace = {
			activeLstats: 0,
			activeWrites: 0,
			activeWriteFailuresRemaining: 0,
			beforeActiveLstat: null,
			cwd,
			events: [],
			failActiveWrite: null,
			failStateAppend: null,
			stateAppendFailuresRemaining: 0,
			notifications: [],
			sentMessages: [],
			stateEntries: [],
		};
		const entries: Array<{
			type: "custom";
			customType: string;
			data: unknown;
		}> = [
			{
				type: "custom",
				customType: "pi-goal-focus",
				data: { version: 1, focusedGoalId: "target", reason: "selected" },
			},
		];
		const tools = new Map<
			string,
			{ execute: (...args: unknown[]) => Promise<unknown> }
		>();
		const commands = new Map<
			string,
			{ handler: (rawArgs: string, ctx: typeof ctx) => Promise<void> | void }
		>();
		let activeTools: string[] = [];
		let terminalInputHandler: ((data: string) => unknown) | null = null;
		const ctx = {
			abort() {},
			cwd,
			getSystemPrompt: () => "",
			hasPendingMessages: () => false,
			hasUI: options.hasUI ?? false,
			isIdle: () => options.isIdle ?? true,
			sessionManager: {
				getLatestCustomEntry(customType: string) {
					return entries.findLast((entry) => entry.customType === customType);
				},
			},
			ui: {
				confirm: async () => options.confirm?.() ?? false,
				notify(message: string, level: string) {
					trace.notifications.push({ level, message });
				},
				onTerminalInput(handler: (data: string) => unknown) {
					terminalInputHandler = handler;
					return () => {
						if (terminalInputHandler === handler) terminalInputHandler = null;
					};
				},
				setStatus() {},
				setWidget() {},
			},
		};
		const handlers = new Map<
			string,
			Array<(event: unknown, ctx: typeof ctx) => unknown>
		>();

		const extensionApi = {
			appendEntry(customType: string, data: unknown) {
				if (customType === "pi-goal-state") {
					trace.events.push("checkpoint-attempt");
					if (trace.failStateAppend) {
						const error = trace.failStateAppend;
						trace.failStateAppend = null;
						throw error;
					}
					if (trace.stateAppendFailuresRemaining > 0) {
						trace.stateAppendFailuresRemaining--;
						throw new Error("injected-state-append-failure");
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
			registerCommand(
				name: string,
				command: {
					handler: (rawArgs: string, ctx: typeof ctx) => Promise<void> | void;
				},
			) {
				commands.set(name, command);
			},
			registerMessageRenderer() {},
			registerTool(tool: {
				name: string;
				execute: (...args: unknown[]) => Promise<unknown>;
			}) {
				tools.set(tool.name, tool);
			},
			sendMessage(message: { content?: unknown; details?: unknown }) {
				trace.sentMessages.push({
					content: message?.content,
					details: message?.details,
				});
			},
			sendUserMessage() {},
			setActiveTools(next: string[]) {
				activeTools = next;
			},
		};
		goalExtension(
			extensionApi as never,
			options.runCompletionAuditor
				? { runCompletionAuditor: options.runCompletionAuditor as never }
				: {},
		);
		const core = (
			extensionApi as unknown as {
				_goalCore: {
					auditAbortController: AbortController | null;
					auditAnimationTimer: ReturnType<typeof setInterval> | null;
					auditProgress: unknown | null;
				};
			}
		)._goalCore;

		return {
			activePath: absoluteActivePath,
			core,
			async emit(name: string, event: unknown = {}) {
				let result: unknown;
				for (const handler of handlers.get(name) ?? [])
					result = await handler(event, ctx);
				return result;
			},
			readGoal: () => parseGoalFile(absoluteActivePath),
			async runCommand(name: string, rawArgs = "") {
				const command = commands.get(name);
				assert(command, `Goal-X did not register /${name}`);
				return command.handler(rawArgs, ctx);
			},
			runTerminalInput(data: string) {
				assert(
					terminalInputHandler,
					"Goal-X did not register terminal input handling",
				);
				return terminalInputHandler(data);
			},
			async runTool(name: string, params: Record<string, unknown>) {
				const tool = tools.get(name);
				assert(tool, `Goal-X did not register ${name}`);
				return tool.execute("test-call", params, undefined, () => {}, ctx);
			},
			trace,
		};
	}

	const ledgerBuilderFailure = createHarness("ledger-builder-failure");
	currentTrace = ledgerBuilderFailure.trace;
	await ledgerBuilderFailure.emit("session_start", { reason: "new" });
	const ledgerBuilderWarnings: string[] = [];
	const ledgerBuilderConsoleWarn = console.warn;
	let ledgerBuilderFaults = 0;
	console.warn = (...parts: unknown[]) => {
		ledgerBuilderWarnings.push(parts.map(String).join(" "));
	};
	let ledgerBuilderOutcome: { ok: boolean } = { ok: false };
	try {
		const service = (
			ledgerBuilderFailure.core as unknown as {
				goalService: {
					apply(
						ctx: { cwd: string },
						spec: unknown,
					): { ok: boolean };
				};
			}
		).goalService;
		ledgerBuilderOutcome = service.apply(
			{ cwd: ledgerBuilderFailure.trace.cwd },
			{
				reconcile: false,
				mutate: (goal: Record<string, unknown>) => ({
					...goal,
					objective: "committed despite ledger builder failure",
				}),
				ledger: () => {
					ledgerBuilderFaults++;
					throw new Error("injected-ledger-builder-failure");
				},
			},
		);
	} finally {
		console.warn = ledgerBuilderConsoleWarn;
	}
	assert.equal(ledgerBuilderFaults, 1);
	assert.equal(ledgerBuilderOutcome.ok, true);
	assert.equal(
		ledgerBuilderFailure.readGoal()?.objective,
		"committed despite ledger builder failure",
	);
	assert.match(
		ledgerBuilderWarnings.join("\n"),
		/ledger diagnostic: Ledger spec error during goal mutation: Error: injected-ledger-builder-failure/,
		"a throwing post-commit ledger builder must remain observable",
	);

	const partialBatch = createHarness("partial-ledger-batch");
	const partialBatchLedgerPath = join(partialBatch.trace.cwd, ".pi/goals/goal_events.jsonl");
	const partialBatchEvents = [
		{ type: "goal_focused" as const, goalId: "target", reason: "partial-first", at: "partial-1" },
		{ type: "goal_unfocused" as const, reason: "partial-second", at: "partial-2" },
	];
	const firstPartialLineBytes = Buffer.byteLength(`${JSON.stringify(partialBatchEvents[0])}\n`);
	let partialWriteInjected = false;
	const partialWarnings: string[] = [];
	const partialOriginalConsoleWarn = console.warn;
	const partialBatchBefore = readGoalLedger(
		{ cwd: partialBatch.trace.cwd },
		{ maxEvents: 8 },
	);
	assert.equal(partialBatchBefore.validEvents, 0);
	ledgerIoProbe = { path: partialBatchLedgerPath, opens: 0, readOperations: 0, bytesRead: 0 };
	mutableFs.writeSync = ((
		fd: number,
		buffer: Uint8Array,
		offset: number,
		length: number,
		position: number | null,
	) => {
		if (probedLedgerFds.has(fd) && !partialWriteInjected) {
			partialWriteInjected = true;
			originalWriteSync(fd, buffer, offset, Math.min(length, firstPartialLineBytes), position);
			throw Object.assign(new Error("injected-partial-batch-write"), { code: "EIO" });
		}
		return originalWriteSync(fd, buffer, offset, length, position);
	}) as typeof mutableFs.writeSync;
	console.warn = (...parts: unknown[]) => partialWarnings.push(parts.map(String).join(" "));
	syncBuiltinESMExports();
	try {
		(partialBatch.core as unknown as {
			goalService: { appendEvents(ctx: { cwd: string }, events: typeof partialBatchEvents): void };
		}).goalService.appendEvents({ cwd: partialBatch.trace.cwd }, partialBatchEvents);
	} finally {
		console.warn = partialOriginalConsoleWarn;
		mutableFs.writeSync = originalWriteSync;
		ledgerIoProbe = null;
		syncBuiltinESMExports();
	}
	assert.equal(partialWriteInjected, true);
	const partialBatchLedger = readGoalLedger({ cwd: partialBatch.trace.cwd }, { maxEvents: 8 });
	assert.equal(
		partialBatchLedger.events.filter((event) => event.type === "goal_focused" && event.reason === "partial-first").length,
		1,
		"an ambiguous written prefix must not be duplicated by individual fallback appends",
	);
	assert.equal(partialBatchLedger.events.some((event) => event.type === "goal_unfocused" && event.reason === "partial-second"), false);
	invalidateGoalLedgerCache();
	const partialBatchCold = readGoalLedger({ cwd: partialBatch.trace.cwd }, { maxEvents: 8 });
	assert.deepEqual(
		partialBatchLedger,
		partialBatchCold,
		"an ambiguous append must invalidate the warm ledger view before returning its error",
	);
	assert.match(partialWarnings.join("\n"), /ambiguous batch was not retried/);

	const committedLedgerWorkdir = join(workdir, "committed-ledger-close");
	const committedLedgerDir = join(committedLedgerWorkdir, ".pi/goals");
	const committedLedgerPath = join(committedLedgerDir, "goal_events.jsonl");
	mkdirSync(committedLedgerDir, { recursive: true });
	writeFileSync(committedLedgerPath, "", "utf8");
	assert.equal(
		readGoalLedger({ cwd: committedLedgerWorkdir }, { maxEvents: 8 }).validEvents,
		0,
	);
	const committedLedgerCloseSync = mutableFs.closeSync;
	let committedLedgerCloseFaults = 0;
	let committedLedgerAttempts = 1;
	ledgerIoProbe = {
		path: committedLedgerPath,
		opens: 0,
		readOperations: 0,
		bytesRead: 0,
	};
	mutableFs.closeSync = ((fd: number) => {
		const isLedgerFd = probedLedgerFds.has(fd);
		const result = committedLedgerCloseSync(fd);
		if (isLedgerFd && committedLedgerCloseFaults === 0) {
			committedLedgerCloseFaults++;
			throw Object.assign(
				new Error("injected-ledger-close-after-commit"),
				{ code: "EIO" },
			);
		}
		return result;
	}) as typeof mutableFs.closeSync;
	syncBuiltinESMExports();
	const committedLedgerEvent = {
		type: "goal_focused" as const,
		goalId: "target",
		reason: "committed-close",
		at: "committed-close",
	};
	let committedLedgerResult: { ok: boolean; error?: unknown } = { ok: false };
	try {
		committedLedgerResult = appendGoalEvent(
			{ cwd: committedLedgerWorkdir },
			committedLedgerEvent,
		);
		if (!committedLedgerResult.ok) {
			committedLedgerAttempts++;
			committedLedgerResult = appendGoalEvent(
				{ cwd: committedLedgerWorkdir },
				committedLedgerEvent,
			);
		}
	} finally {
		mutableFs.closeSync = committedLedgerCloseSync;
		ledgerIoProbe = null;
		syncBuiltinESMExports();
	}
	assert.equal(
		committedLedgerCloseFaults,
		1,
		"the ledger close mutation must fire after the append is committed",
	);
	assert.equal(
		committedLedgerAttempts,
		1,
		"a committed ledger append must not be reported as retryable",
	);
	assert.deepEqual(committedLedgerResult, { ok: true });
	const committedLedgerWarm = readGoalLedger(
		{ cwd: committedLedgerWorkdir },
		{ maxEvents: 8 },
	);
	assert.equal(committedLedgerWarm.validEvents, 1);
	assert.deepEqual(committedLedgerWarm.events, [committedLedgerEvent]);
	invalidateGoalLedgerCache();
	const committedLedgerCold = readGoalLedger(
		{ cwd: committedLedgerWorkdir },
		{ maxEvents: 8 },
	);
	assert.deepEqual(
		committedLedgerCold,
		committedLedgerWarm,
		"warm and cold ledger views must adopt the same committed event once",
	);

	const recoveryCommandFailure = createHarness("recovery-command-failure", {
		confirm: () => true,
	});
	currentTrace = recoveryCommandFailure.trace;
	const recoveryCommandLockDir = join(
		recoveryCommandFailure.trace.cwd,
		".pi/goals/.locks",
	);
	const recoveryCommandLockPath = join(recoveryCommandLockDir, "command-failure.lock");
	mkdirSync(recoveryCommandLockDir, { recursive: true });
	writeFileSync(
		recoveryCommandLockPath,
		JSON.stringify({ pid: -1, startedAt: "2000-01-01T00:00:00.000Z" }),
		"utf8",
	);
	const recoveryCommandOriginalUnlinkSync = mutableFs.unlinkSync;
	mutableFs.unlinkSync = ((filePath: import("node:fs").PathLike) => {
		if (String(filePath).includes(".command-failure.lock.recovery-")) {
			throw Object.assign(new Error("injected-command-repair-failure"), { code: "EACCES" });
		}
		return recoveryCommandOriginalUnlinkSync(filePath);
	}) as typeof mutableFs.unlinkSync;
	syncBuiltinESMExports();
	try {
		await recoveryCommandFailure.runCommand("goal-recovery", "repair");
	} finally {
		mutableFs.unlinkSync = recoveryCommandOriginalUnlinkSync;
		syncBuiltinESMExports();
	}
	const recoveryCommandNotice = recoveryCommandFailure.trace.notifications.at(-1);
	assert.equal(recoveryCommandNotice?.level, "warning");
	assert.match(
		recoveryCommandNotice?.message ?? "",
		/0 operation\(s\) applied, 1 failed[\s\S]*remove_stale_lock\/unlink[\s\S]*injected-command-repair-failure/,
	);

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

	const runtimeGoal = {
		id: "runtime-goal",
		objective: "runtime retry lifecycle",
		status: "active" as const,
		autoContinue: true,
		revision: 7,
		usage: { tokensUsed: 0, activeSeconds: 0 },
		sisyphus: false,
		createdAt: "runtime-created",
		updatedAt: "runtime-updated",
	};
	const compactGoalCheckpointContext =
		goalEventsModule.compactGoalCheckpointContext as
			| ((messages: readonly unknown[], goal: typeof runtimeGoal | null) => unknown[] | null)
			| undefined;
	if (hasV2Checkpoints) {
		assert.equal(typeof compactGoalCheckpointContext, "function");
		const ordinaryMessage = { role: "assistant", content: "retain me" };
		const latestCheckpoint = {
			role: "custom",
			customType: "pi-goal-event",
			content: "objective leak from latest checkpoint",
			display: true,
			details: {
				version: 1,
				goalId: runtimeGoal.id,
				objective: "objective leak",
			},
		};
		const compacted = compactGoalCheckpointContext?.(
			[
				{
					role: "custom",
					customType: "pi-goal-event",
					content: "obsolete checkpoint",
					details: { goalId: "obsolete-goal" },
				},
				ordinaryMessage,
				latestCheckpoint,
			],
			runtimeGoal,
		);
		assert(compacted);
		assert.equal(compacted.length, 2);
		assert.equal(compacted[0], ordinaryMessage);
		assert.deepEqual(compacted[1], {
			...latestCheckpoint,
			content:
				'<pi_goal_continuation goal_id="runtime-goal" kind="checkpoint" v="2"/>',
			display: false,
			details: {
				version: 2,
				kind: "checkpoint",
				goalId: runtimeGoal.id,
				currentGoalId: runtimeGoal.id,
				currentStatus: "active",
			},
		});
		assert.doesNotMatch(JSON.stringify(compacted), /objective leak/);
	} else {
		assert.equal(compactGoalCheckpointContext, undefined);
	}
	{
		const sent: Array<{ content: string; details: Record<string, unknown> }> = [];
		const runtime = new GoalRuntime({
			sendFollowUp: (content: string, details: Record<string, unknown>) =>
				sent.push({ content, details }),
			getGoal: () => runtimeGoal,
			isActionable: () => true,
		});
		const readyCtx = {
			cwd: workdir,
			hasPendingMessages: () => false,
			isIdle: () => true,
			signal: new AbortController().signal,
		};
		runtime.queueContinuation(readyCtx as never, runtimeGoal);
		mock.timers.tick(0);
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), true);
		assert.equal(sent.length, 1);
		const firstTimestamp = sent[0]?.details.timestamp;
		assert.equal(typeof firstTimestamp, "number");
		if (hasV2Checkpoints) {
			assert.deepEqual(sent[0], {
				content:
					'<pi_goal_continuation goal_id="runtime-goal" kind="checkpoint" v="2"/>',
				details: {
					version: 2,
					kind: "checkpoint",
					goalId: runtimeGoal.id,
					status: "active",
					revision: 7,
					checkpointSeq: 1,
					timestamp: firstTimestamp,
				},
			});
			assert.equal("objective" in sent[0]!.details, false);
			runtime.clearContinuationState();
			runtime.queueContinuation(readyCtx as never, runtimeGoal);
			mock.timers.tick(0);
			assert.equal(sent[1]?.details.checkpointSeq, 2);
			assert.equal("objective" in sent[1]!.details, false);
		} else {
			assert.match(sent[0]!.content, /runtime retry lifecycle/);
			assert.deepEqual(sent[0]!.details, {
				kind: "checkpoint",
				goalId: runtimeGoal.id,
				status: "active",
				objective: runtimeGoal.objective,
				timestamp: firstTimestamp,
			});
		}
		runtime.clearContinuationState();
	}
	{
		let actionabilityChecks = 0;
		const runtime = new GoalRuntime({
			sendFollowUp: () => assert.fail("a goal that became non-actionable must not send"),
			getGoal: () => runtimeGoal,
			isActionable: () => ++actionabilityChecks === 1,
		});
		const readyCtx = {
			cwd: workdir,
			hasPendingMessages: () => false,
			isIdle: () => true,
			signal: new AbortController().signal,
		};
		runtime.queueContinuation(readyCtx as never, runtimeGoal);
		mock.timers.tick(0);
		assert.equal(actionabilityChecks, 2);
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), false);
	}
	{
		const sent: unknown[] = [];
		const controller = new AbortController();
		const runtime = new GoalRuntime({
			sendFollowUp: (...args: unknown[]) => sent.push(args),
			getGoal: () => runtimeGoal,
			isActionable: () => true,
		});
		const busyCtx = {
			cwd: workdir,
			hasPendingMessages: () => true,
			isIdle: () => false,
			signal: controller.signal,
		};
		runtime.queueContinuation(busyCtx as never, runtimeGoal);
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), true);
		controller.abort();
		mock.timers.tick(CONTINUATION_IDLE_RETRY_MS);
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), false);
		assert.equal(sent.length, 0);
	}
	{
		let signalReads = 0;
		const runtime = new GoalRuntime({
			sendFollowUp: () => assert.fail("stale context must not send"),
			getGoal: () => runtimeGoal,
			isActionable: () => true,
		});
		const staleCtx = {
			cwd: workdir,
			hasPendingMessages: () => true,
			isIdle: () => false,
			get signal() {
				signalReads++;
				if (signalReads > 1) throw new Error("terminal gone");
				return new AbortController().signal;
			},
		};
		runtime.queueContinuation(staleCtx as never, runtimeGoal);
		assert.doesNotThrow(() => mock.timers.tick(CONTINUATION_IDLE_RETRY_MS));
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), false);
	}
	{
		const runtime = new GoalRuntime({
			sendFollowUp: () => {
				throw new Error("terminal gone during dispatch");
			},
			getGoal: () => runtimeGoal,
			isActionable: () => true,
		});
		const readyCtx = {
			cwd: workdir,
			hasPendingMessages: () => false,
			isIdle: () => true,
			signal: new AbortController().signal,
		};
		runtime.queueContinuation(readyCtx as never, runtimeGoal);
		assert.doesNotThrow(() => mock.timers.tick(0));
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), false);
	}
	{
		const runtime = new GoalRuntime({
			sendFollowUp: () => assert.fail("missing goal must not send"),
			getGoal: () => null,
			isActionable: () => true,
		});
		const readyCtx = {
			cwd: workdir,
			hasPendingMessages: () => false,
			isIdle: () => true,
			signal: new AbortController().signal,
		};
		runtime.queueContinuation(readyCtx as never, runtimeGoal);
		mock.timers.tick(0);
		assert.equal(runtime.continuationPendingFor(runtimeGoal.id), false);
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

	const concurrentUsage = createHarness("concurrent-usage");
	currentTrace = concurrentUsage.trace;
	await concurrentUsage.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await concurrentUsage.emit("tool_execution_end");
	const concurrentDiskGoal = concurrentUsage.readGoal();
	assert(concurrentDiskGoal);
	writeFileSync(
		concurrentUsage.activePath,
		serializeGoalFile({
			...concurrentDiskGoal,
			usage: { tokensUsed: 5, activeSeconds: 5 },
			revision: (concurrentDiskGoal.revision ?? 0) + 1,
		}),
		"utf8",
	);
	mock.timers.tick(1000);
	await concurrentUsage.emit("session_tree");
	await concurrentUsage.emit("session_shutdown");
	assert.deepEqual(
		concurrentUsage.readGoal()?.usage,
		{ tokensUsed: 5, activeSeconds: 7 },
		"session-tree reload must add the local two-second delta to concurrent disk usage",
	);

	const completedTurnRetry = createHarness("completed-turn-retry");
	currentTrace = completedTurnRetry.trace;
	await completedTurnRetry.emit("session_start", { reason: "new" });
	await completedTurnRetry.emit("turn_start");
	completedTurnRetry.trace.beforeActiveLstat = {
		remaining: 1,
		run() {
			const error = new Error(
				"one-shot completed-turn reconciliation failure",
			) as NodeJS.ErrnoException;
			error.code = "EIO";
			throw error;
		},
	};
	await completedTurnRetry.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 4, output: 6 },
		},
	});
	assert.equal(completedTurnRetry.readGoal()?.usage.tokensUsed, 0);
	mock.timers.tick(accountingIntervalMs);
	assert.equal(
		completedTurnRetry.readGoal()?.usage.tokensUsed,
		10,
		"a transient reconciliation failure must retain the completed turn's tokens",
	);
	mock.timers.tick(accountingIntervalMs);
	await completedTurnRetry.emit("session_shutdown");
	assert.equal(
		completedTurnRetry.readGoal()?.usage.tokensUsed,
		10,
		"completed-turn retry ownership must charge exactly once",
	);

	const committedRenameUsage = createHarness("committed-rename-usage");
	currentTrace = committedRenameUsage.trace;
	await committedRenameUsage.emit("session_start", { reason: "new" });
	const committedRenameSync = mutableFs.renameSync;
	let committedRenameFaults = 0;
	let committedRenameAttempts = 1;
	mutableFs.renameSync = ((oldPath, newPath) => {
		const result = committedRenameSync(oldPath, newPath);
		if (
			committedRenameFaults === 0
			&& String(oldPath).includes(".write-")
			&& String(oldPath).endsWith("/content")
			&& String(newPath) === committedRenameUsage.activePath
		) {
			committedRenameFaults++;
			throw Object.assign(
				new Error("injected-error-after-successful-atomic-rename"),
				{ code: "EIO" },
			);
		}
		return result;
	}) as typeof mutableFs.renameSync;
	syncBuiltinESMExports();
	let committedRenameOutcome: { ok: boolean; retryable?: boolean } = {
		ok: false,
	};
	try {
		const service = (
			committedRenameUsage.core as unknown as {
				goalService: {
					addUsage(
						ctx: { cwd: string },
						goalId: string,
						delta: { tokens?: number; seconds?: number },
					): { ok: boolean; retryable?: boolean };
				};
			}
		).goalService;
		committedRenameOutcome = service.addUsage(
			{ cwd: committedRenameUsage.trace.cwd },
			"target",
			{ tokens: 7 },
		);
		if (!committedRenameOutcome.ok && committedRenameOutcome.retryable) {
			committedRenameAttempts++;
			committedRenameOutcome = service.addUsage(
				{ cwd: committedRenameUsage.trace.cwd },
				"target",
				{ tokens: 7 },
			);
		}
	} finally {
		mutableFs.renameSync = committedRenameSync;
		syncBuiltinESMExports();
	}
	assert.equal(
		committedRenameFaults,
		1,
		"the rename ambiguity mutation must fire after the real rename",
	);
	assert.equal(
		committedRenameAttempts,
		1,
		"an adopted atomic rename must not make additive usage retry",
	);
	assert.equal(committedRenameOutcome.ok, true);
	assert.equal(committedRenameUsage.readGoal()?.usage.tokensUsed, 7);
	assert.equal(committedRenameUsage.trace.activeWrites, 1);
	assert.deepEqual(
		readdirSync(join(committedRenameUsage.trace.cwd, ".pi/goals"))
			.filter((name) => name.includes(".write-")),
		[],
		"an adopted atomic rename must not leak a temp name",
	);

	const committedCloseUsage = createHarness("committed-close-usage");
	currentTrace = committedCloseUsage.trace;
	await committedCloseUsage.emit("session_start", { reason: "new" });
	const committedCloseOpenSync = mutableFs.openSync;
	const committedCloseRenameSync = mutableFs.renameSync;
	const committedCloseCloseSync = mutableFs.closeSync;
	const committedTempFds = new Map<string, number>();
	const publishedTempFds = new Set<number>();
	let committedCloseFaults = 0;
	let committedCloseAttempts = 1;
	mutableFs.openSync = ((filePath, flags, mode) => {
		const opened = committedCloseOpenSync(filePath, flags, mode);
		const openedPath = String(filePath);
		if (
			openedPath.includes(".write-")
			&& openedPath.endsWith("/content")
		) committedTempFds.set(openedPath, opened);
		return opened;
	}) as typeof mutableFs.openSync;
	mutableFs.renameSync = ((oldPath, newPath) => {
		committedCloseRenameSync(oldPath, newPath);
		const tempFd = committedTempFds.get(String(oldPath));
		if (
			tempFd !== undefined
			&& String(newPath) === committedCloseUsage.activePath
		) publishedTempFds.add(tempFd);
	}) as typeof mutableFs.renameSync;
	mutableFs.closeSync = ((fd: number) => {
		const wasPublishedTemp = publishedTempFds.delete(fd);
		for (const [tempPath, tempFd] of committedTempFds) {
			if (tempFd === fd) committedTempFds.delete(tempPath);
		}
		const result = committedCloseCloseSync(fd);
		if (wasPublishedTemp && committedCloseFaults === 0) {
			committedCloseFaults++;
			throw Object.assign(
				new Error("injected-close-error-after-atomic-publication"),
				{ code: "EBADF" },
			);
		}
		return result;
	}) as typeof mutableFs.closeSync;
	syncBuiltinESMExports();
	let committedCloseOutcome: {
		ok: boolean;
		retryable?: boolean;
	} = { ok: false };
	try {
		const service = (
			committedCloseUsage.core as unknown as {
				goalService: {
					addUsage(
						ctx: { cwd: string },
						goalId: string,
						delta: { tokens?: number; seconds?: number },
					): { ok: boolean; retryable?: boolean };
				};
			}
		).goalService;
		committedCloseOutcome = service.addUsage(
			{ cwd: committedCloseUsage.trace.cwd },
			"target",
			{ tokens: 7 },
		);
		if (!committedCloseOutcome.ok && committedCloseOutcome.retryable) {
			committedCloseAttempts++;
			committedCloseOutcome = service.addUsage(
				{ cwd: committedCloseUsage.trace.cwd },
				"target",
				{ tokens: 7 },
			);
		}
	} finally {
		mutableFs.openSync = committedCloseOpenSync;
		mutableFs.renameSync = committedCloseRenameSync;
		mutableFs.closeSync = committedCloseCloseSync;
		syncBuiltinESMExports();
	}
	assert.equal(
		committedCloseFaults,
		1,
		"the atomic-write close mutation must fire after canonical publication",
	);
	assert.equal(
		committedCloseAttempts,
		1,
		"a post-publication close error must not make additive usage retry",
	);
	assert.equal(committedCloseOutcome.ok, true);
	assert.equal(
		committedCloseUsage.readGoal()?.usage.tokensUsed,
		7,
		"the committed additive delta must be adopted exactly once",
	);
	assert.equal(committedCloseUsage.trace.activeWrites, 1);
	assert.deepEqual(
		readdirSync(join(committedCloseUsage.trace.cwd, ".pi/goals"))
			.filter((name) => name.includes(".write-")),
		[],
		"post-publication close failure must not leak an atomic-write temp",
	);

	const committedLockReleaseUsage = createHarness("committed-lock-release-usage");
	currentTrace = committedLockReleaseUsage.trace;
	await committedLockReleaseUsage.emit("session_start", { reason: "new" });
	const committedLockReleasePath = join(
		committedLockReleaseUsage.trace.cwd,
		".pi/goals/.locks/target.lock",
	);
	const committedLockReleaseGatePath = `${committedLockReleasePath}.gate`;
	const committedLockReleaseOpenSync = mutableFs.openSync;
	const committedLockReleaseConsoleWarn = console.warn;
	const committedLockReleaseWarnings: string[] = [];
	let committedLockReleaseFaults = 0;
	let committedLockReleaseAttempts = 1;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const readOnly = typeof flags === "number"
			&& (flags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (String(filePath) === committedLockReleasePath && readOnly) {
			committedLockReleaseFaults++;
			throw Object.assign(new Error("injected-committed-lock-release-failure"), { code: "EIO" });
		}
		return committedLockReleaseOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	console.warn = (...parts: unknown[]) => {
		committedLockReleaseWarnings.push(parts.map(String).join(" "));
	};
	syncBuiltinESMExports();
	let committedLockReleaseOutcome: { ok: boolean; retryable?: boolean } = { ok: false };
	try {
		const service = (
			committedLockReleaseUsage.core as unknown as {
				goalService: {
					addUsage(
						ctx: { cwd: string },
						goalId: string,
						delta: { tokens?: number; seconds?: number },
					): { ok: boolean; retryable?: boolean };
				};
			}
		).goalService;
		committedLockReleaseOutcome = service.addUsage(
			{ cwd: committedLockReleaseUsage.trace.cwd },
			"target",
			{ tokens: 7 },
		);
		if (!committedLockReleaseOutcome.ok && committedLockReleaseOutcome.retryable) {
			committedLockReleaseAttempts++;
			committedLockReleaseOutcome = service.addUsage(
				{ cwd: committedLockReleaseUsage.trace.cwd },
				"target",
				{ tokens: 7 },
			);
		}
	} finally {
		console.warn = committedLockReleaseConsoleWarn;
		mutableFs.openSync = committedLockReleaseOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(committedLockReleaseFaults, 3, "lock release must exhaust its bounded retries");
	assert.equal(
		committedLockReleaseAttempts,
		1,
		"a release failure after an authoritative additive write must not invite a retry",
	);
	assert.equal(committedLockReleaseOutcome.ok, true);
	assert.equal(committedLockReleaseUsage.readGoal()?.usage.tokensUsed, 7);
	assert.equal(committedLockReleaseUsage.trace.activeWrites, 1);
	assert.match(
		committedLockReleaseWarnings.join("\n"),
		/lock diagnostic: Goal lock release failed.*injected-committed-lock-release-failure/i,
	);
	assert.equal(existsSync(committedLockReleasePath), true, "persistent failure must retain the main ownership file");
	assert.equal(existsSync(committedLockReleaseGatePath), false);
	unlinkSync(committedLockReleasePath);

	const compoundUsageFailure = createHarness("compound-usage-and-lock-release-failure");
	currentTrace = compoundUsageFailure.trace;
	await compoundUsageFailure.emit("session_start", { reason: "new" });
	compoundUsageFailure.trace.failActiveWrite = Object.assign(
		new Error("injected-compound-usage-write-failure"),
		{ code: "EIO" },
	);
	compoundUsageFailure.trace.activeWriteFailuresRemaining = 1;
	const compoundUsageLockPath = join(
		compoundUsageFailure.trace.cwd,
		".pi/goals/.locks/target.lock",
	);
	const compoundUsageGatePath = `${compoundUsageLockPath}.gate`;
	const compoundUsageOpenSync = mutableFs.openSync;
	let compoundUsageReleaseFaults = 0;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const readOnly = typeof flags === "number"
			&& (flags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (String(filePath) === compoundUsageLockPath && readOnly) {
			compoundUsageReleaseFaults++;
			throw Object.assign(new Error("injected-compound-usage-release-failure"), { code: "EIO" });
		}
		return compoundUsageOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let compoundUsageOutcome: { ok: boolean; retryable?: boolean; message?: string };
	try {
		const service = (
			compoundUsageFailure.core as unknown as {
				goalService: {
					addUsage(
						ctx: { cwd: string },
						goalId: string,
						delta: { tokens?: number },
					): { ok: boolean; retryable?: boolean; message?: string };
				};
			}
		).goalService;
		compoundUsageOutcome = service.addUsage(
			{ cwd: compoundUsageFailure.trace.cwd },
			"target",
			{ tokens: 7 },
		);
	} finally {
		mutableFs.openSync = compoundUsageOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(compoundUsageReleaseFaults, 3);
	assert.equal(compoundUsageOutcome.ok, false);
	assert.equal(compoundUsageOutcome.retryable, true);
	assert.match(compoundUsageOutcome.message ?? "", /injected-compound-usage-write-failure/);
	assert.match(compoundUsageOutcome.message ?? "", /injected-compound-usage-release-failure/);
	assert.equal(compoundUsageFailure.readGoal()?.usage.tokensUsed, 0);
	assert.equal(existsSync(compoundUsageLockPath), true);
	assert.equal(existsSync(compoundUsageGatePath), false);
	unlinkSync(compoundUsageLockPath);

	const addUsageBaselineFailure = createHarness("add-usage-baseline-failure", {
		autoContinue: true,
	});
	currentTrace = addUsageBaselineFailure.trace;
	await addUsageBaselineFailure.emit("session_start", { reason: "new" });
	await addUsageBaselineFailure.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	mock.timers.tick(1000);
	await addUsageBaselineFailure.emit("tool_execution_end");
	const addUsageExternal = addUsageBaselineFailure.readGoal();
	assert(addUsageExternal);
	writeFileSync(
		addUsageBaselineFailure.activePath,
		serializeGoalFile({
			...addUsageExternal,
			usage: { tokensUsed: 0, activeSeconds: 5 },
			revision: (addUsageExternal.revision ?? 0) + 1,
		}),
		"utf8",
	);
	addUsageBaselineFailure.trace.failActiveWrite = new Error(
		"first-aborted-usage-write-fails",
	);
	await addUsageBaselineFailure.emit("agent_end", {
		messages: [
			{
				role: "assistant",
				stopReason: "aborted",
				usage: { input: 3, output: 4 },
			},
		],
	});
	mock.timers.tick(accountingIntervalMs);
	assert.deepEqual(
		addUsageBaselineFailure.readGoal()?.usage,
		{ tokensUsed: 7, activeSeconds: 6 },
		"a failed addUsage write must not advance the baseline and discard local usage on retry",
	);

	const mergedBudget = createHarness("merged-budget", {
		goal: { tokenBudget: 10 },
	});
	currentTrace = mergedBudget.trace;
	await mergedBudget.emit("session_start", { reason: "new" });
	await mergedBudget.emit("turn_start");
	await mergedBudget.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 1, output: 1 },
		},
	});
	const mergedBudgetExternal = mergedBudget.readGoal();
	assert(mergedBudgetExternal);
	writeFileSync(
		mergedBudget.activePath,
		serializeGoalFile({
			...mergedBudgetExternal,
			usage: { tokensUsed: 9, activeSeconds: 0 },
			revision: (mergedBudgetExternal.revision ?? 0) + 1,
		}),
		"utf8",
	);
	mock.timers.tick(accountingIntervalMs);
	assert.equal(mergedBudget.readGoal()?.usage.tokensUsed, 11);
	assert.equal(mergedBudget.readGoal()?.status, "budget_limited");
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: mergedBudget.trace.cwd },
			"target",
		).events.filter((event) => event.type === "goal_budget_limited").length,
		1,
		"post-merge budget enforcement must emit exactly one transition",
	);

	const abortedBudget = createHarness("aborted-budget", {
		autoContinue: true,
		goal: { tokenBudget: 10 },
	});
	currentTrace = abortedBudget.trace;
	await abortedBudget.emit("session_start", { reason: "new" });
	await abortedBudget.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	await abortedBudget.emit("agent_end", {
		messages: [
			{
				role: "assistant",
				stopReason: "aborted",
				usage: { input: 4, output: 6 },
			},
		],
	});
	assert.equal(abortedBudget.readGoal()?.usage.tokensUsed, 10);
	assert.equal(abortedBudget.readGoal()?.status, "budget_limited");
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: abortedBudget.trace.cwd },
			"target",
		).events.filter((event) => event.type === "goal_budget_limited").length,
		1,
	);

	let budgetResumeConfirmations = 0;
	const budgetResume = createHarness("budget-resume-gate", {
		hasUI: true,
		goal: {
			status: "paused",
			autoContinue: false,
			tokenBudget: 10,
			usage: { tokensUsed: 10, activeSeconds: 0 },
		},
		confirm: () => {
			budgetResumeConfirmations++;
			return true;
		},
	});
	currentTrace = budgetResume.trace;
	await budgetResume.emit("session_start", { reason: "resume" });
	assert.equal(budgetResumeConfirmations, 0);
	assert.equal(budgetResume.readGoal()?.status, "budget_limited");
	await budgetResume.runCommand("goal-resume");
	assert.match(
		budgetResume.trace.notifications.map((item) => item.message).join("\n"),
		/Raise or remove the budget/,
	);
	const raisedBudget = budgetResume.readGoal();
	assert(raisedBudget);
	writeFileSync(
		budgetResume.activePath,
		serializeGoalFile({
			...raisedBudget,
			tokenBudget: 20,
			revision: (raisedBudget.revision ?? 0) + 1,
		}),
		"utf8",
	);
	await budgetResume.runCommand("goal-resume");
	assert.equal(budgetResume.readGoal()?.status, "active");

	const beforeStartBudget = createHarness("before-start-budget", {
		autoContinue: true,
		goal: { tokenBudget: 10 },
	});
	currentTrace = beforeStartBudget.trace;
	await beforeStartBudget.emit("session_start", { reason: "new" });
	const legacyBudget = beforeStartBudget.readGoal();
	assert(legacyBudget);
	writeFileSync(
		beforeStartBudget.activePath,
		serializeGoalFile({
			...legacyBudget,
			status: "active",
			usage: { tokensUsed: 10, activeSeconds: 0 },
			revision: (legacyBudget.revision ?? 0) + 1,
		}),
		"utf8",
	);
	const budgetStartResult = await beforeStartBudget.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	assert.equal(beforeStartBudget.readGoal()?.status, "budget_limited");
	assert.match(JSON.stringify(budgetStartResult), /PI GOAL BUDGET LIMITED/);

	const bufferedConcurrentStatus = createHarness("buffered-concurrent-status");
	currentTrace = bufferedConcurrentStatus.trace;
	await bufferedConcurrentStatus.emit("session_start", { reason: "new" });
	await bufferedConcurrentStatus.emit("turn_start");
	mock.timers.tick(1000);
	await bufferedConcurrentStatus.emit("tool_execution_end");
	const concurrentlyPaused = bufferedConcurrentStatus.readGoal();
	assert(concurrentlyPaused);
	writeFileSync(
		bufferedConcurrentStatus.activePath,
		serializeGoalFile({
			...concurrentlyPaused,
			status: "paused",
			revision: (concurrentlyPaused.revision ?? 0) + 1,
		}),
		"utf8",
	);
	mock.timers.tick(accountingIntervalMs - 1000);
	assert.equal(
		bufferedConcurrentStatus.readGoal()?.status,
		"paused",
		"an accounting-only turn flush must not resurrect a concurrently paused goal",
	);
	assert.equal(bufferedConcurrentStatus.readGoal()?.usage.activeSeconds, 1);

	const repeatedExternalPrompt = createHarness("repeated-external-prompt");
	currentTrace = repeatedExternalPrompt.trace;
	await repeatedExternalPrompt.emit("session_start", { reason: "new" });
	await repeatedExternalPrompt.emit("turn_start");
	const firstExternalPrompt = repeatedExternalPrompt.readGoal();
	assert(firstExternalPrompt);
	writeFileSync(
		repeatedExternalPrompt.activePath,
		serializeGoalFile({
			...firstExternalPrompt,
			objective: "first external objective",
			revision: (firstExternalPrompt.revision ?? 0) + 1,
		}),
		"utf8",
	);
	mock.timers.tick(1000);
	await repeatedExternalPrompt.emit("tool_execution_end");
	const secondExternalPrompt = repeatedExternalPrompt.readGoal();
	assert(secondExternalPrompt);
	writeFileSync(
		repeatedExternalPrompt.activePath,
		serializeGoalFile({
			...secondExternalPrompt,
			objective: "second external objective",
			revision: (secondExternalPrompt.revision ?? 0) + 1,
		}),
		"utf8",
	);
	mock.timers.tick(accountingIntervalMs - 1000);
	assert.equal(
		repeatedExternalPrompt.readGoal()?.objective,
		"second external objective",
		"reconciliation must advance the turn base before a later external edit",
	);
	assert.equal(repeatedExternalPrompt.readGoal()?.usage.activeSeconds, 1);

	const concurrentTasks = createHarness("concurrent-tasks", {
		withTasks: true,
	});
	currentTrace = concurrentTasks.trace;
	await concurrentTasks.emit("session_start", { reason: "new" });
	await concurrentTasks.emit("turn_start");
	await concurrentTasks.runTool("update_goal_task", {
		task_id: "task-a",
		status: "complete",
		evidence: "local evidence",
	});
	const externalTaskGoal = concurrentTasks.readGoal();
	assert(externalTaskGoal?.taskList);
	externalTaskGoal.taskList.tasks[1] = {
		...externalTaskGoal.taskList.tasks[1],
		status: "complete",
		completedAt: new Date(Date.now()).toISOString(),
		evidence: "external evidence",
	};
	externalTaskGoal.revision = (externalTaskGoal.revision ?? 0) + 1;
	writeFileSync(
		concurrentTasks.activePath,
		serializeGoalFile(externalTaskGoal),
		"utf8",
	);
	await concurrentTasks.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 0, output: 0 },
		},
	});
	assert.deepEqual(
		concurrentTasks.readGoal()?.taskList?.tasks.map((task) => task.status),
		["complete", "complete"],
		"local and external updates to different task ids must both survive",
	);

	const repeatedSkip = createHarness("repeated-task-skip", {
		withTasks: true,
	});
	currentTrace = repeatedSkip.trace;
	await repeatedSkip.emit("session_start", { reason: "new" });
	await repeatedSkip.runTool("update_goal_task", {
		task_id: "task-a",
		status: "skipped",
		reason: "not required",
	});
	const skippedBytes = readFileSync(repeatedSkip.activePath);
	const skippedStat = statSync(repeatedSkip.activePath);
	const skippedWrites = repeatedSkip.trace.activeWrites;
	const skippedEvents = readGoalLedgerForGoal(
		{ cwd: repeatedSkip.trace.cwd },
		"target",
	).events.filter((event) => event.type === "task_skipped").length;
	await repeatedSkip.runTool("update_goal_task", {
		task_id: "task-a",
		status: "skipped",
		reason: "not required",
	});
	assert.equal(repeatedSkip.trace.activeWrites, skippedWrites);
	assert.deepEqual(readFileSync(repeatedSkip.activePath), skippedBytes);
	assert.equal(statSync(repeatedSkip.activePath).ino, skippedStat.ino);
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: repeatedSkip.trace.cwd },
			"target",
		).events.filter((event) => event.type === "task_skipped").length,
		skippedEvents,
		"an already-skipped task must not be rewritten or emit a duplicate event",
	);

	const concurrentSkip = createHarness("concurrent-task-skip-retry", {
		withTasks: true,
	});
	currentTrace = concurrentSkip.trace;
	await concurrentSkip.emit("session_start", { reason: "new" });
	const externallySkipped = concurrentSkip.readGoal();
	assert(externallySkipped?.taskList);
	externallySkipped.taskList.tasks[0] = {
		...externallySkipped.taskList.tasks[0]!,
		status: "skipped",
		skippedAt: new Date(Date.now()).toISOString(),
		skipReason: "other session",
	};
	externallySkipped.updatedAt = new Date(Date.now()).toISOString();
	externallySkipped.revision = (externallySkipped.revision ?? 0) + 1;
	const externalSkipBytes = Buffer.from(serializeGoalFile(externallySkipped), "utf8");
	const concurrentSkipWrites = concurrentSkip.trace.activeWrites;
	const concurrentSkipGatePath = join(
		concurrentSkip.trace.cwd,
		".pi/goals/.locks/target.lock.gate",
	);
	const concurrentSkipOpenSync = mutableFs.openSync;
	let concurrentSkipInjected = false;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		if (!concurrentSkipInjected && String(filePath) === concurrentSkipGatePath) {
			concurrentSkipInjected = true;
			writeFileSync(concurrentSkip.activePath, externalSkipBytes);
		}
		return concurrentSkipOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	try {
		await concurrentSkip.runTool("update_goal_task", {
			task_id: "task-a",
			status: "skipped",
			reason: "local retry",
		});
	} finally {
		mutableFs.openSync = concurrentSkipOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(concurrentSkipInjected, true);
	assert.equal(concurrentSkip.trace.activeWrites, concurrentSkipWrites);
	assert.deepEqual(readFileSync(concurrentSkip.activePath), externalSkipBytes);
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: concurrentSkip.trace.cwd },
			"target",
		).events.filter((event) => event.type === "task_skipped").length,
		0,
		"a retry that discovers an externally skipped task must be an idempotent no-op",
	);

	const retryReleaseFailure = createHarness("concurrent-task-retry-release-failure", {
		withTasks: true,
	});
	currentTrace = retryReleaseFailure.trace;
	await retryReleaseFailure.emit("session_start", { reason: "new" });
	const retryReleaseExternal = retryReleaseFailure.readGoal();
	assert(retryReleaseExternal);
	retryReleaseExternal.revision = (retryReleaseExternal.revision ?? 0) + 1;
	const retryReleaseExternalBytes = Buffer.from(serializeGoalFile(retryReleaseExternal), "utf8");
	const retryReleaseLockDir = join(retryReleaseFailure.trace.cwd, ".pi/goals/.locks");
	const retryReleaseMainPath = join(retryReleaseLockDir, "target.lock");
	const retryReleaseGatePath = `${retryReleaseMainPath}.gate`;
	const retryReleaseOpenSync = mutableFs.openSync;
	let retryReleaseGateCreates = 0;
	let retryReleaseFaults = 0;
	let retryReleaseUpdateCalls = 0;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		const numericFlags = typeof flags === "number" ? flags : 0;
		const readOnly = typeof flags === "number"
			&& (numericFlags & (mutableFs.constants.O_WRONLY | mutableFs.constants.O_RDWR)) === 0;
		if (String(filePath) === retryReleaseGatePath && !readOnly) {
			retryReleaseGateCreates++;
			if (retryReleaseGateCreates === 1) {
				writeFileSync(retryReleaseFailure.activePath, retryReleaseExternalBytes);
			}
		}
		if (String(filePath) === retryReleaseMainPath && readOnly) {
			retryReleaseFaults++;
			throw Object.assign(new Error("injected-task-retry-release-failure"), { code: "EIO" });
		}
		return retryReleaseOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	let retryReleaseThrown: unknown;
	try {
		const service = (
			retryReleaseFailure.core as unknown as {
				goalService: {
					updateTask(ctx: { cwd: string }, spec: {
						taskId: string;
						update(task: unknown): unknown;
					}): unknown;
				};
			}
		).goalService;
		service.updateTask(
			{ cwd: retryReleaseFailure.trace.cwd },
			{
				taskId: "task-a",
				update: (task) => {
					retryReleaseUpdateCalls++;
					return task;
				},
			},
		);
	} catch (error) {
		retryReleaseThrown = error;
	} finally {
		mutableFs.openSync = retryReleaseOpenSync;
		syncBuiltinESMExports();
	}
	assert.match(String(retryReleaseThrown), /injected-task-retry-release-failure/);
	assert.equal(retryReleaseFaults, 3, "the initial lock release must use its bounded retry count");
	assert.equal(
		retryReleaseGateCreates,
		1,
		"a requested task retry must not reacquire while its first lock remains held",
	);
	assert.equal(retryReleaseUpdateCalls, 0, "no task mutation may run after the failed retry release");
	assert.deepEqual(readFileSync(retryReleaseFailure.activePath), retryReleaseExternalBytes);
	assert.equal(existsSync(retryReleaseMainPath), true);
	assert.equal(existsSync(retryReleaseGatePath), false);
	unlinkSync(retryReleaseMainPath);

	const taskUsageBaseline = createHarness("task-usage-baseline", {
		withTasks: true,
	});
	currentTrace = taskUsageBaseline.trace;
	await taskUsageBaseline.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await taskUsageBaseline.emit("tool_execution_end");
	await taskUsageBaseline.runTool("update_goal_task", {
		task_id: "task-a",
		status: "complete",
		evidence: "baseline evidence",
	});
	mock.timers.tick(1000);
	await taskUsageBaseline.emit("tool_execution_end");
	await taskUsageBaseline.emit("session_tree");
	assert.equal(
		taskUsageBaseline.readGoal()?.usage.activeSeconds,
		2,
		"a task write must advance the additive usage baseline",
	);

	const replaceFocusUsage = createHarness("replace-focus-usage");
	currentTrace = replaceFocusUsage.trace;
	await replaceFocusUsage.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await replaceFocusUsage.emit("tool_execution_end");
	await replaceFocusUsage.runTool("create_goal", {
		objective: "create a second explicit goal",
	});
	assert.equal(
		replaceFocusUsage.readGoal()?.usage.activeSeconds,
		1,
		"creating a new focus must first persist charged usage for the old goal",
	);

	const lifecycleUsage = createHarness("lifecycle-usage", {
		autoContinue: true,
	});
	currentTrace = lifecycleUsage.trace;
	await lifecycleUsage.emit("session_start", { reason: "new" });
	await lifecycleUsage.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	mock.timers.tick(1000);
	await lifecycleUsage.emit("tool_execution_end");
	await lifecycleUsage.emit("agent_end", { messages: [] });
	await lifecycleUsage.emit("session_shutdown");
	assert.equal(
		lifecycleUsage.readGoal()?.usage.activeSeconds,
		1,
		"agent-end reconciliation must retain a coalesced accounting charge",
	);

	const completionUsage = createHarness("completion-usage", {
		autoContinue: true,
		skipAuditor: true,
	});
	currentTrace = completionUsage.trace;
	await completionUsage.emit("session_start", { reason: "new" });
	await completionUsage.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	mock.timers.tick(1000);
	await completionUsage.runTool("update_goal", { status: "complete" });
	assert.equal(completionUsage.readGoal()?.status, "complete");
	assert.equal(
		completionUsage.readGoal()?.usage.activeSeconds,
		1,
		"completion must retain accounting accrued while the auditor path runs",
	);

	for (const fault of ["open", "read"] as const) {
		const auditLedgerFailure = createHarness(`audit-ledger-${fault}-failure`, {
			autoContinue: true,
		});
		currentTrace = auditLedgerFailure.trace;
		await auditLedgerFailure.emit("session_start", { reason: "new" });
		const injected = Object.assign(new Error(`injected-ledger-${fault}-failure`), {
			code: "EIO",
		});
		ledgerIoProbe = {
			path: join(auditLedgerFailure.trace.cwd, ".pi/goals/goal_events.jsonl"),
			opens: 0,
			readOperations: 0,
			bytesRead: 0,
			...(fault === "open"
				? { failOpen: injected, failOpenAfterOpens: 1 }
				: { failRead: injected, failReadAfterOperations: 1 }),
		};
		try {
			await assert.rejects(
				auditLedgerFailure.runTool("update_goal", { status: "complete" }),
				new RegExp(`injected-ledger-${fault}-failure`),
				`a ledger ${fault} failure after audit setup must propagate`,
			);
		} finally {
			ledgerIoProbe = null;
		}
		assert.equal(auditLedgerFailure.core.auditProgress, null);
		assert.equal(auditLedgerFailure.core.auditAnimationTimer, null);
		assert.equal(auditLedgerFailure.core.auditAbortController, null);
		assert.equal(
			auditLedgerFailure.readGoal()?.status,
			"active",
			`failed audit setup after a ledger ${fault} error must leave the goal active`,
		);
	}

	let auditAccountingRevision: ReturnType<typeof createHarness>;
	auditAccountingRevision = createHarness("audit-accounting-revision", {
		autoContinue: true,
		runCompletionAuditor: async () => {
			const external = auditAccountingRevision.readGoal();
			assert(external);
			writeFileSync(
				auditAccountingRevision.activePath,
				serializeGoalFile({
					...external,
					usage: { ...external.usage, tokensUsed: 7 },
					revision: (external.revision ?? 0) + 1,
				}),
				"utf8",
			);
			return {
				approved: true,
				output: "Auditor approved accounting drift.",
				model: "test/auditor",
			};
		},
	});
	currentTrace = auditAccountingRevision.trace;
	await auditAccountingRevision.emit("session_start", { reason: "new" });
	await auditAccountingRevision.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	const accountingApproval = await auditAccountingRevision.runTool(
		"update_goal",
		{ status: "complete" },
	);
	assert.match(
		JSON.stringify(accountingApproval),
		/Auditor approved accounting drift/,
	);
	assert.equal(auditAccountingRevision.readGoal()?.status, "complete");
	assert.equal(auditAccountingRevision.readGoal()?.usage.tokensUsed, 7);
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: auditAccountingRevision.trace.cwd },
			"target",
		).events.filter(
			(event) => event.type === "audit_result" && event.verdict === "approved",
		).length,
		1,
	);

	let auditSemanticChange: ReturnType<typeof createHarness>;
	auditSemanticChange = createHarness("audit-semantic-change", {
		autoContinue: true,
		runCompletionAuditor: async () => {
			writeFileSync(
				auditSemanticChange.activePath,
				readFileSync(auditSemanticChange.activePath, "utf8").replace(
					"# Goal Prompt\n\nexercise bounded accounting persistence",
					"# Goal Prompt\n\nsemantic edit during audit",
				),
				"utf8",
			);
			return {
				approved: true,
				output: "Stale approval must not persist.",
				model: "test/auditor",
			};
		},
	});
	currentTrace = auditSemanticChange.trace;
	await auditSemanticChange.emit("session_start", { reason: "new" });
	await auditSemanticChange.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	const staleApproval = await auditSemanticChange.runTool("update_goal", {
		status: "complete",
	});
	assert.match(JSON.stringify(staleApproval), /audited goal changed/);
	assert.equal(auditSemanticChange.readGoal()?.status, "active");
	assert.equal(
		auditSemanticChange.readGoal()?.objective,
		"semantic edit during audit",
	);
	assert.equal(
		readGoalLedgerForGoal(
			{ cwd: auditSemanticChange.trace.cwd },
			"target",
		).events.some(
			(event) => event.type === "audit_result" && event.verdict === "approved",
		),
		false,
	);
	assert.equal(
		auditSemanticChange.trace.sentMessages.some(
			(message) =>
				(message.details as { phase?: string } | undefined)?.phase ===
				"approved",
		),
		false,
	);

	const repeatedSessionStart = createHarness("repeated-session-start");
	currentTrace = repeatedSessionStart.trace;
	await repeatedSessionStart.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await repeatedSessionStart.emit("tool_execution_end");
	await repeatedSessionStart.emit("session_start", { reason: "resume" });
	assert.equal(
		repeatedSessionStart.readGoal()?.usage.activeSeconds,
		1,
		"session start must flush pending accounting before destructive reload",
	);
	const externalSessionUsage = repeatedSessionStart.readGoal();
	assert(externalSessionUsage);
	writeFileSync(
		repeatedSessionStart.activePath,
		serializeGoalFile({
			...externalSessionUsage,
			usage: { tokensUsed: 10, activeSeconds: 10 },
			revision: (externalSessionUsage.revision ?? 0) + 1,
		}),
		"utf8",
	);
	await repeatedSessionStart.emit("session_start", { reason: "resume" });
	await repeatedSessionStart.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	await repeatedSessionStart.emit("session_compact");
	mock.timers.tick(accountingIntervalMs);
	assert.equal(
		repeatedSessionStart.readGoal()?.usage.activeSeconds,
		10,
		"fresh session loads must reset the additive usage baseline",
	);

	let resumePromptEdit: ReturnType<typeof createHarness>;
	resumePromptEdit = createHarness("resume-prompt-edit", {
		hasUI: true,
		goal: {
			objective: "resume old objective",
			status: "paused",
			autoContinue: false,
		},
		confirm: () => {
			writeFileSync(
				resumePromptEdit.activePath,
				readFileSync(resumePromptEdit.activePath, "utf8").replace(
					"# Goal Prompt\n\nresume old objective",
					"# Goal Prompt\n\nresume new objective",
				),
				"utf8",
			);
			return true;
		},
	});
	currentTrace = resumePromptEdit.trace;
	await resumePromptEdit.emit("session_start", { reason: "resume" });
	assert.equal(resumePromptEdit.readGoal()?.objective, "resume new objective");
	assert.equal(resumePromptEdit.readGoal()?.status, "paused");
	assert.equal(resumePromptEdit.trace.activeWrites, 0);
	assert.match(
		resumePromptEdit.trace.notifications.map((item) => item.message).join("\n"),
		/changed while resuming/,
	);

	const promptRefresh = createHarness("prompt-refresh");
	currentTrace = promptRefresh.trace;
	await promptRefresh.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await promptRefresh.emit("tool_execution_end");
	writeFileSync(
		promptRefresh.activePath,
		readFileSync(promptRefresh.activePath, "utf8").replace(
			"exercise bounded accounting persistence",
			"exercise externally edited prompt persistence",
		),
		"utf8",
	);
	await promptRefresh.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 0, output: 0 },
		},
	});
	await promptRefresh.emit("session_shutdown");
	assert.equal(
		promptRefresh.readGoal()?.usage.activeSeconds,
		1,
		"a prompt-only state checkpoint must not cancel pending accounting",
	);
	assert.equal(promptRefresh.trace.activeWrites, 1);

	const concurrentNoOp = createHarness("concurrent-no-op");
	currentTrace = concurrentNoOp.trace;
	await concurrentNoOp.emit("session_start", { reason: "new" });
	const externallyAdvanced = concurrentNoOp.readGoal();
	assert(externallyAdvanced);
	writeFileSync(
		concurrentNoOp.activePath,
		serializeGoalFile({
			...externallyAdvanced,
			revision: (externallyAdvanced.revision ?? 0) + 1,
		}),
		"utf8",
	);
	await concurrentNoOp.emit("session_compact");
	assert.deepEqual(
		tickCapturingErrors(accountingIntervalMs),
		[],
		"a concurrent revision with no local delta is an adopted no-op",
	);
	assert.equal(concurrentNoOp.trace.activeWrites, 0);
	assert.deepEqual(tickCapturingErrors(accountingIntervalMs), []);

	const lostPendingCheckpoint = createHarness("lost-pending-checkpoint", {
		withTasks: true,
	});
	currentTrace = lostPendingCheckpoint.trace;
	await lostPendingCheckpoint.emit("session_start", { reason: "new" });
	lostPendingCheckpoint.trace.failStateAppend = new Error(
		"checkpoint-before-deletion",
	);
	await lostPendingCheckpoint.runTool("update_goal_task", {
		task_id: "task-a",
		status: "complete",
		evidence: "deleted checkpoint evidence",
	});
	unlinkSync(lostPendingCheckpoint.activePath);
	await lostPendingCheckpoint.emit("tool_execution_end");
	await lostPendingCheckpoint.emit("session_shutdown");
	assert.equal(lostPendingCheckpoint.trace.stateEntries.length, 0);
	assert.equal(
		lostPendingCheckpoint.trace.events.filter(
			(event) => event === "checkpoint-attempt",
		).length,
		1,
		"authoritative goal loss must discard its stale pending checkpoint",
	);
	assert.deepEqual(tickCapturingErrors(accountingIntervalMs), []);

	const malformedBeforeFlush = createHarness("malformed-before-flush");
	currentTrace = malformedBeforeFlush.trace;
	await malformedBeforeFlush.emit("session_start", { reason: "new" });
	const validGoalBytes = readFileSync(malformedBeforeFlush.activePath, "utf8");
	mock.timers.tick(1000);
	await malformedBeforeFlush.emit("tool_execution_end");
	writeFileSync(malformedBeforeFlush.activePath, "not a goal record\n", "utf8");
	assert.match(
		tickCapturingErrors(accountingIntervalMs - 1000).join("\n"),
		/Could not read a valid goal record/,
		"malformed existing files must retry rather than look deleted",
	);
	writeFileSync(malformedBeforeFlush.activePath, validGoalBytes, "utf8");
	assert.deepEqual(tickCapturingErrors(accountingIntervalMs), []);
	assert.equal(malformedBeforeFlush.readGoal()?.usage.activeSeconds, 1);

	const deletedDuringTurn = createHarness("deleted-during-turn");
	currentTrace = deletedDuringTurn.trace;
	await deletedDuringTurn.emit("session_start", { reason: "new" });
	await deletedDuringTurn.emit("turn_start");
	await deletedDuringTurn.runTool("update_goal", {
		status: "paused",
		reason: "buffer a semantic mutation before external deletion",
	});
	unlinkSync(deletedDuringTurn.activePath);
	await deletedDuringTurn.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	await deletedDuringTurn.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 0, output: 0 },
		},
	});
	assert.equal(
		existsSync(deletedDuringTurn.activePath),
		false,
		"a buffered turn must not resurrect an externally deleted goal",
	);

	const deletedBeforeFlush = createHarness("deleted-before-flush");
	currentTrace = deletedBeforeFlush.trace;
	await deletedBeforeFlush.emit("session_start", { reason: "new" });
	await deletedBeforeFlush.emit("turn_start");
	mock.timers.tick(1000);
	await deletedBeforeFlush.emit("tool_execution_end");
	unlinkSync(deletedBeforeFlush.activePath);
	assert.deepEqual(tickCapturingErrors(accountingIntervalMs - 1000), []);
	assert.equal(
		existsSync(deletedBeforeFlush.activePath),
		false,
		"an accounting flush must not resurrect an externally deleted goal",
	);
	const lostGoalResult = await deletedBeforeFlush.runTool("get_goal", {});
	assert.match(
		JSON.stringify(lostGoalResult),
		/no goal is (?:set|focused)/i,
		"confirmed deletion must clear the focused goal",
	);
	assert.deepEqual(tickCapturingErrors(accountingIntervalMs), []);

	const completedUsageGone = createHarness("completed-usage-gone", { hasUI: true });
	currentTrace = completedUsageGone.trace;
	await completedUsageGone.emit("session_start", { reason: "new" });
	await completedUsageGone.emit("turn_start");
	unlinkSync(completedUsageGone.activePath);
	await completedUsageGone.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "stop",
			usage: { input: 2, output: 5 },
		},
	});
	assert(
		completedUsageGone.trace.notifications.some(({ level, message }) =>
			level === "error" && /Could not record 7 completed-turn tokens for target/.test(message)),
		"terminal completed-turn usage loss must be surfaced explicitly",
	);
	assert.equal(existsSync(completedUsageGone.activePath), false);

	const deletedBeforeAbortedTurn = createHarness(
		"deleted-before-aborted-turn",
		{ autoContinue: true },
	);
	currentTrace = deletedBeforeAbortedTurn.trace;
	await deletedBeforeAbortedTurn.emit("session_start", { reason: "new" });
	await deletedBeforeAbortedTurn.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	unlinkSync(deletedBeforeAbortedTurn.activePath);
	await deletedBeforeAbortedTurn.emit("turn_end", {
		message: {
			role: "assistant",
			stopReason: "aborted",
			usage: { input: 2, output: 3 },
		},
	});
	await assert.doesNotReject(
		deletedBeforeAbortedTurn.emit("before_agent_start", {
			prompt: "",
			systemPrompt: "base",
		}),
		"terminal goal loss must settle late aborted usage instead of bricking later starts",
	);
	const deletedBeforeAbortedAttempts =
		deletedBeforeAbortedTurn.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length;
	mock.timers.tick(accountingIntervalMs * 2);
	assert.equal(
		deletedBeforeAbortedTurn.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length,
		deletedBeforeAbortedAttempts,
		"terminal aborted usage must not re-arm the retry timer",
	);

	const deletedAfterAbortedFailure = createHarness(
		"deleted-after-aborted-failure",
		{ autoContinue: true },
	);
	currentTrace = deletedAfterAbortedFailure.trace;
	await deletedAfterAbortedFailure.emit("session_start", { reason: "new" });
	await deletedAfterAbortedFailure.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	deletedAfterAbortedFailure.trace.failActiveWrite = new Error(
		"transient-aborted-write",
	);
	await deletedAfterAbortedFailure.emit("agent_end", {
		messages: [
			{
				role: "assistant",
				stopReason: "aborted",
				usage: { input: 2, output: 3 },
			},
		],
	});
	unlinkSync(deletedAfterAbortedFailure.activePath);
	const deletedAfterAbortedAttempts =
		deletedAfterAbortedFailure.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length;
	mock.timers.tick(accountingIntervalMs);
	assert.equal(
		deletedAfterAbortedFailure.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length,
		deletedAfterAbortedAttempts,
		"a transient aborted-usage retry must terminate when the authoritative record disappears",
	);
	mock.timers.tick(accountingIntervalMs * 2);
	assert.equal(
		deletedAfterAbortedFailure.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length,
		deletedAfterAbortedAttempts,
	);

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
		"checkpoint-attempt",
		"checkpoint",
	]);
	assert.equal(scheduledCheckpointFailure.trace.activeWrites, 1);
	assert.equal(scheduledCheckpointFailure.trace.stateEntries.length, 1);
	await scheduledCheckpointFailure.emit("session_shutdown");
	assert.equal(scheduledCheckpointFailure.trace.activeWrites, 2);
	assert.equal(scheduledCheckpointFailure.trace.stateEntries.length, 2);
	assert.deepEqual(scheduledCheckpointFailure.trace.events.slice(-4), [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);

	const checkpointThenAccounting = createHarness("checkpoint-then-accounting", {
		withTasks: true,
	});
	currentTrace = checkpointThenAccounting.trace;
	await checkpointThenAccounting.emit("session_start", { reason: "new" });
	checkpointThenAccounting.trace.failStateAppend = new Error(
		"checkpoint-before-accounting",
	);
	await checkpointThenAccounting.runTool("update_goal_task", {
		task_id: "task-a",
		status: "complete",
		evidence: "checkpoint retry evidence",
	});
	mock.timers.tick(1000);
	await checkpointThenAccounting.emit("tool_execution_end");
	mock.timers.tick(accountingIntervalMs - 1000);
	assert.equal(
		checkpointThenAccounting.readGoal()?.usage.activeSeconds,
		1,
		"checkpoint retry must be followed by any newer dirty accounting",
	);
	assert.equal(checkpointThenAccounting.trace.activeWrites, 2);
	assert.equal(checkpointThenAccounting.trace.stateEntries.length, 2);
	assert.deepEqual(checkpointThenAccounting.trace.events.slice(-6), [
		"checkpoint-attempt",
		"checkpoint",
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);

	const checkpointBeforeStart = createHarness("checkpoint-before-start", {
		withTasks: true,
	});
	currentTrace = checkpointBeforeStart.trace;
	await checkpointBeforeStart.emit("session_start", { reason: "new" });
	checkpointBeforeStart.trace.failStateAppend = new Error(
		"initial-checkpoint-failure",
	);
	await checkpointBeforeStart.runTool("update_goal_task", {
		task_id: "task-a",
		status: "complete",
		evidence: "checkpoint should not gate starts",
	});
	checkpointBeforeStart.trace.failStateAppend = new Error(
		"checkpoint-retry-during-start",
	);
	await assert.doesNotReject(
		checkpointBeforeStart.emit("before_agent_start", {
			prompt: "",
			systemPrompt: "base",
		}),
		"a retryable checkpoint append must not brick before_agent_start",
	);
	assert.equal(
		checkpointBeforeStart.trace.events.filter(
			(event) => event === "checkpoint-attempt",
		).length,
		2,
	);
	mock.timers.tick(accountingIntervalMs);
	assert.equal(checkpointBeforeStart.trace.stateEntries.length, 1);
	assert.equal(
		checkpointBeforeStart.trace.events.filter(
			(event) => event === "checkpoint-attempt",
		).length,
		3,
	);

	const transition = createHarness("forced-transition");
	currentTrace = transition.trace;
	await transition.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await transition.emit("tool_execution_end");
	await transition.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	await transition.runTool("update_goal", {
		status: "paused",
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
		activeFailure.runTool("update_goal", {
			status: "paused",
			reason: "force a write failure",
		}),
		/active-write-failure/,
	);
	assert.equal(activeFailure.trace.activeWrites, 0);
	assert.equal(activeFailure.trace.stateEntries.length, 0);
	assert.deepEqual(activeFailure.trace.events, ["active-file-attempt"]);
	assert.equal(activeFailure.readGoal()?.status, "active");
	await activeFailure.emit("session_shutdown");
	assert.deepEqual(activeFailure.trace.events, [
		"active-file-attempt",
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint",
	]);
	assert.equal(activeFailure.readGoal()?.status, "active");
	mock.timers.tick(accountingIntervalMs);
	assert.equal(activeFailure.trace.events.length, 5);

	const checkpointFailure = createHarness("checkpoint-failure", {
		hasUI: true,
	});
	currentTrace = checkpointFailure.trace;
	await checkpointFailure.emit("session_start", { reason: "new" });
	await checkpointFailure.emit("before_agent_start", {
		prompt: "",
		systemPrompt: "base",
	});
	checkpointFailure.trace.failStateAppend = new Error("checkpoint-failure");
	await checkpointFailure.runTool("update_goal", {
		status: "paused",
		reason: "force a checkpoint failure",
	});
	assert.equal(checkpointFailure.trace.activeWrites, 1);
	assert.equal(checkpointFailure.trace.stateEntries.length, 0);
	assert.deepEqual(checkpointFailure.trace.events, [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
	]);
	assert.equal(checkpointFailure.readGoal()?.status, "paused");
	await checkpointFailure.emit("session_shutdown");
	assert.deepEqual(checkpointFailure.trace.events, [
		"active-file-attempt",
		"active-file",
		"checkpoint-attempt",
		"checkpoint-attempt",
		"checkpoint",
	]);
	assert.equal(checkpointFailure.readGoal()?.status, "paused");
	mock.timers.tick(accountingIntervalMs);
	assert.equal(checkpointFailure.trace.events.length, 5);

	const shutdownActiveRetry = createHarness("shutdown-active-retry");
	currentTrace = shutdownActiveRetry.trace;
	await shutdownActiveRetry.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await shutdownActiveRetry.emit("tool_execution_end");
	shutdownActiveRetry.trace.activeWriteFailuresRemaining = 1;
	await shutdownActiveRetry.emit("session_shutdown");
	assert.equal(
		shutdownActiveRetry.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length,
		2,
		"shutdown must retry a transient active-record write within its bounded drain",
	);
	assert.equal(shutdownActiveRetry.trace.stateEntries.length, 1);

	const shutdownCheckpointRetry = createHarness("shutdown-checkpoint-retry");
	currentTrace = shutdownCheckpointRetry.trace;
	await shutdownCheckpointRetry.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await shutdownCheckpointRetry.emit("tool_execution_end");
	shutdownCheckpointRetry.trace.failStateAppend = new Error(
		"shutdown-checkpoint-once",
	);
	await shutdownCheckpointRetry.emit("session_shutdown");
	assert.equal(shutdownCheckpointRetry.trace.activeWrites, 1);
	assert.equal(
		shutdownCheckpointRetry.trace.events.filter(
			(event) => event === "checkpoint-attempt",
		).length,
		2,
		"a checkpoint failure created by the shutdown write must drain in the same shutdown",
	);
	assert.equal(shutdownCheckpointRetry.trace.stateEntries.length, 1);

	const shutdownPersistentFailure = createHarness(
		"shutdown-persistent-failure",
	);
	currentTrace = shutdownPersistentFailure.trace;
	await shutdownPersistentFailure.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await shutdownPersistentFailure.emit("tool_execution_end");
	shutdownPersistentFailure.trace.activeWriteFailuresRemaining = 3;
	await assert.rejects(
		shutdownPersistentFailure.emit("session_shutdown"),
		/injected-active-write-failure/,
		"persistent shutdown failure must be explicit after the bounded retry count",
	);
	assert.equal(
		shutdownPersistentFailure.trace.events.filter(
			(event) => event === "active-file-attempt",
		).length,
		3,
		"shutdown persistence must make exactly three attempts",
	);
	const persistentShutdownEvents =
		shutdownPersistentFailure.trace.events.length;
	mock.timers.tick(accountingIntervalMs * 2);
	assert.equal(
		shutdownPersistentFailure.trace.events.length,
		persistentShutdownEvents,
		"bounded shutdown must leave no live retry timer",
	);

	const shutdownMalformedRecord = createHarness("shutdown-malformed-record");
	currentTrace = shutdownMalformedRecord.trace;
	await shutdownMalformedRecord.emit("session_start", { reason: "new" });
	mock.timers.tick(1000);
	await shutdownMalformedRecord.emit("tool_execution_end");
	writeFileSync(
		shutdownMalformedRecord.activePath,
		"not a goal record\n",
		"utf8",
	);
	const malformedShutdownOpenSync = mutableFs.openSync;
	let malformedShutdownOpens = 0;
	mutableFs.openSync = ((filePath: import("node:fs").PathLike, flags: import("node:fs").OpenMode, mode?: import("node:fs").Mode) => {
		if (String(filePath) === shutdownMalformedRecord.activePath) malformedShutdownOpens++;
		return malformedShutdownOpenSync(filePath, flags, mode);
	}) as typeof mutableFs.openSync;
	syncBuiltinESMExports();
	try {
		await assert.rejects(
			shutdownMalformedRecord.emit("session_shutdown"),
			/Could not read a valid goal record/,
			"shutdown must surface an unreadable authoritative record after draining",
		);
	} finally {
		mutableFs.openSync = malformedShutdownOpenSync;
		syncBuiltinESMExports();
	}
	assert.equal(
		malformedShutdownOpens,
		4,
		"shutdown must enter the three-attempt drain even when initial reconciliation throws",
	);
	const malformedShutdownEvents = shutdownMalformedRecord.trace.events.length;
	const malformedShutdownLstatsAfterDrain =
		shutdownMalformedRecord.trace.activeLstats;
	mock.timers.tick(accountingIntervalMs * 2);
	assert.equal(
		shutdownMalformedRecord.trace.events.length,
		malformedShutdownEvents,
	);
	assert.equal(
		shutdownMalformedRecord.trace.activeLstats,
		malformedShutdownLstatsAfterDrain,
		"shutdown reconciliation failure must leave no retry timer alive",
	);

	console.log(
		JSON.stringify({
			accountingUpdates,
			activeFileWrites: cadence.trace.activeWrites,
			boundedEvents: bounded.events.length,
			cardinalityHeapDelta,
			cardinalityRssDelta,
			distinctGoalCount,
			ledgerBytes: readFileSync(ledgerPath).byteLength,
			ledgerEvents: requestedEvents,
			rssDeltaBytes: rssAfter - rssBefore,
			sessionCheckpoints: cadence.trace.stateEntries.length,
			targetEvents: target.events.length,
		}),
	);
} finally {
	currentTrace = null;
	ledgerIoProbe = null;
		if (timersEnabled) mock.timers.reset();
		mutableFs.renameSync = originalRenameSync;
		mutableFs.linkSync = originalLinkSync;
	mutableFs.lstatSync = originalLstatSync;
	mutableFs.openSync = originalOpenSync;
	mutableFs.readSync = originalReadSync;
	mutableFs.closeSync = originalCloseSync;
	syncBuiltinESMExports();
	rmSync(workdir, { recursive: true, force: true });
}
