import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const packageRoot = process.env.PI_AGENT_BROWSER_NATIVE_ROOT;
assert(packageRoot, "PI_AGENT_BROWSER_NATIVE_ROOT must name the packaged Browser Native root");
const codingAgentRoot = process.env.PI_CODING_AGENT_ROOT;
assert(codingAgentRoot, "PI_CODING_AGENT_ROOT must name the packaged Pi coding-agent root");

const extensionRelativePath = "dist/extensions/agent-browser/index.js";
const extensionSource = readFileSync(join(packageRoot, extensionRelativePath), "utf8");
const packageVersion = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8")).version;
assert.equal(packageVersion, "0.5.0", "unexpected Browser Native version");
assert.equal(
	extensionSource.match(/sessionManager\.getRecentActiveEntries\(\{ type: "message", limit: 4096 \}\)/g)?.length,
	1,
	"branch restoration must use one item-bounded active-history query",
);
assert.equal(
	extensionSource.match(/customType: "agent-browser-script-session"/g)?.length ?? 0,
	1,
	"script-session lease recovery must use one type-bounded active-history query",
);
assert.equal(
	extensionSource.match(/sessionManager\.getLatestMessage\("user", \{ scope: "active" \}\)/g)?.length,
	2,
	"prompt policy must use active-branch point queries",
);
assert.equal(
	extensionSource.match(
		/for \(const lease of getScriptSessionLeasesFromBranch\(leaseEntries\)\.values\(\)\)/g,
	)?.length ?? 0,
	1,
	"script-session recovery must consume the bounded lease query",
);
assert(!extensionSource.includes("sessionManager.getBranch("), "Browser Native must not hydrate the full branch");

const workdir = mkdtempSync(join(tmpdir(), "pi-agent-browser-bounded-"));
const runtimeRoot = join(workdir, "runtime");
const previousHome = process.env.HOME;

try {
	cpSync(packageRoot, runtimeRoot, { recursive: true });
	const scopedModules = join(runtimeRoot, "node_modules/@earendil-works");
	const peerModules = join(codingAgentRoot, "node_modules");
	mkdirSync(scopedModules, { recursive: true });
	symlinkSync(codingAgentRoot, join(scopedModules, "pi-coding-agent"));
	symlinkSync(join(peerModules, "@earendil-works/pi-ai"), join(scopedModules, "pi-ai"));
	symlinkSync(join(peerModules, "@earendil-works/pi-tui"), join(scopedModules, "pi-tui"));
	symlinkSync(join(peerModules, "typebox"), join(runtimeRoot, "node_modules/typebox"));
	process.env.HOME = workdir;

	const { default: registerBrowser } = await import(join(runtimeRoot, extensionRelativePath));
	const handlers = new Map();
	const tools = [];
	const appendedEntries = [];
	registerBrowser({
		appendEntry(...args) {
			appendedEntries.push(args);
		},
		on(event, handler) {
			const registered = handlers.get(event) ?? [];
			registered.push(handler);
			handlers.set(event, registered);
		},
		registerTool(tool) {
			tools.push(tool);
		},
	});

	const boundedQueries = [];
	const pointQueries = [];
	let leaseEntriesConsumed = 0;
	let leaseCleanupReads = 0;
	let fullBranchCalls = 0;
	const latestUserEntry = {
		id: "user-1",
		parentId: null,
		timestamp: "2026-08-18T00:00:00.000Z",
		type: "message",
		message: { role: "user", content: "Use agent-browser via bash", timestamp: 1 },
	};
	const scriptSessionName = "piab-script-00000000-0000-4000-8000-000000000000";
	const closeCommandArgs = ["--namespace", "", "--session", scriptSessionName, "close"];
	const closedLeaseEntry = {
		customType: "agent-browser-script-session",
		data: {
			cleanup: "closed",
			closeCommandArgs,
			launchAttempted: true,
			sessionName: scriptSessionName,
		},
		type: "custom",
	};
	const { getScriptSessionLeasesFromBranch } = await import(
		join(runtimeRoot, "dist/extensions/agent-browser/lib/orchestration/script-mode.js")
	);
	assert.deepEqual(getScriptSessionLeasesFromBranch([closedLeaseEntry]), new Map([
		[
			scriptSessionName,
			{ cleanup: "closed", closeCommandArgs, launchAttempted: true, sessionName: scriptSessionName },
		],
	]));
	const context = {
		cwd: workdir,
		isProjectTrusted: () => true,
		sessionManager: {
			getBranch() {
				fullBranchCalls += 1;
				return Array.from({ length: 16384 }, (_, index) => ({
					...latestUserEntry,
					id: `history-${index}`,
					message: { ...latestUserEntry.message, content: `${index}:${"x".repeat(4096)}` },
				}));
			},
			getLatestMessage(role, options) {
				pointQueries.push([role, options]);
				return latestUserEntry;
			},
			getRecentActiveEntries(options) {
				boundedQueries.push(options);
				if (!options.customType) return [latestUserEntry];
				const leases = [{
					...closedLeaseEntry,
					data: {
						...closedLeaseEntry.data,
						get cleanup() {
							leaseCleanupReads += 1;
							return "closed";
						},
					},
				}];
				leases[Symbol.iterator] = function* () {
					leaseEntriesConsumed += 1;
					yield leases[0];
				};
				return leases;
			},
			getSessionId: () => "session-1",
		},
	};

	global.gc?.();
	const rssBefore = process.memoryUsage().rss;
	const previousPath = process.env.PATH;
	process.env.PATH = "";
	try {
		for (const handler of handlers.get("session_start") ?? []) await handler({}, context);
		for (const handler of handlers.get("session_tree") ?? []) await handler({}, context);
	} finally {
		if (previousPath === undefined) delete process.env.PATH;
		else process.env.PATH = previousPath;
	}
	let bashToolCallResult;
	for (const handler of handlers.get("tool_call") ?? []) {
		bashToolCallResult = await handler(
			{ input: { command: "agent-browser open https://example.com" }, toolName: "bash" },
			context,
		);
	}
	assert.equal(
		bashToolCallResult,
		undefined,
		"the latest-user point query must preserve an explicit bash opt-in",
	);
	const browserTool = tools.find((tool) => tool.name === "agent_browser");
	assert(browserTool, "Browser Native did not register agent_browser");
	const invalidResult = await browserTool.execute(
		"tool-1",
		{},
		new AbortController().signal,
		() => {},
		context,
	);
	assert.equal(invalidResult?.isError, true, "focused execution must stop at local validation");
	global.gc?.();
	const rssDelta = Math.max(0, process.memoryUsage().rss - rssBefore);

	assert.equal(fullBranchCalls, 0, "Browser Native requested an unbounded branch");
	const messageQuery = { type: "message", limit: 4096 };
	const leaseQuery = { customType: "agent-browser-script-session", limit: 4096 };
	assert.deepEqual(boundedQueries, [messageQuery, leaseQuery, messageQuery, leaseQuery]);
	assert.equal(leaseEntriesConsumed, 2);
	assert.equal(leaseCleanupReads, 2);
	assert.deepEqual(appendedEntries, [], "closed script-session leases must not trigger cleanup writes");
	assert.deepEqual(pointQueries, [
		["user", { scope: "active" }],
		["user", { scope: "active" }],
	]);
	assert(
		rssDelta <= 24 * 1024 * 1024,
		`bounded Browser Native history paths grew RSS by ${rssDelta} bytes`,
	);
} finally {
	if (previousHome === undefined) delete process.env.HOME;
	else process.env.HOME = previousHome;
	rmSync(workdir, { recursive: true, force: true });
}
