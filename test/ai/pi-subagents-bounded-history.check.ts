import { describe, expect, mock, test } from "bun:test";
import assert from "node:assert/strict";
import * as realFs from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";

mock.module("@earendil-works/pi-coding-agent", () => ({
	SessionManager: {
		open() {
			throw new Error("test must inject openSession");
		},
	},
}));

const packageRoot = process.env.PI_SUBAGENTS_ROOT;
assert(
	packageRoot,
	"PI_SUBAGENTS_ROOT must name the packaged pi-subagents root",
);

const {
	alignForkedSessionCwd,
	createForkContextResolver,
	sanitizePersistedFork,
} = await import(join(packageRoot, "src/shared/fork-context.ts"));
const [packageMajor, packageMinor] = (
	JSON.parse(
		realFs.readFileSync(join(packageRoot, "package.json"), "utf-8"),
	) as {
		version: string;
	}
).version
	.split(".")
	.map(Number);
const expectsForkCwdAlignment = packageMajor > 0 || packageMinor >= 50;
const { parseSessionTokens } = await import(
	join(packageRoot, "src/shared/session-tokens.ts")
);

type Entry = Record<string, unknown> & { id?: string };

function writeAll(fd: number, value: string | Buffer): void {
	const bytes = typeof value === "string" ? Buffer.from(value) : value;
	let offset = 0;
	while (offset < bytes.length) {
		const written = realFs.writeSync(fd, bytes, offset, bytes.length - offset);
		assert(written > 0, "fixture write made no progress");
		offset += written;
	}
}

function encodeJsonl(entries: Entry[], finalNewline = true): Buffer {
	return Buffer.from(
		`${entries.map((entry) => JSON.stringify(entry)).join("\n")}${finalNewline ? "\n" : ""}`,
	);
}

function decodeJsonl(filePath: string): Entry[] {
	return realFs
		.readFileSync(filePath, "utf-8")
		.split("\n")
		.filter((line) => line.trim())
		.map((line) => JSON.parse(line) as Entry);
}

function tempFiles(dir: string, sessionFile: string): string[] {
	const prefix = `.${basename(sessionFile)}.`;
	return realFs
		.readdirSync(dir)
		.filter((name) => name.startsWith(prefix) && name.endsWith(".tmp"));
}

function forkHarness(input: {
	dir: string;
	branchFile: string;
	branchBytes: Buffer;
	deferPersistence?: boolean;
}) {
	const parentFile = join(input.dir, "parent.jsonl");
	realFs.writeFileSync(
		parentFile,
		'{"type":"session","version":3,"id":"parent"}\n',
	);
	let creates = 0;
	let flushes = 0;
	let closes = 0;
	let compatibilityReads = 0;
	const sourceManager = {
		createBranchedSession() {
			creates++;
			if (!input.deferPersistence)
				realFs.writeFileSync(input.branchFile, input.branchBytes);
			return input.branchFile;
		},
		flush() {
			flushes++;
			realFs.writeFileSync(input.branchFile, input.branchBytes);
		},
		close() {
			closes++;
		},
		getEntries() {
			compatibilityReads++;
			throw new Error("getEntries compatibility path was used");
		},
		getHeader() {
			compatibilityReads++;
			throw new Error("getHeader fallback was used");
		},
	};
	const resolver = createForkContextResolver(
		{
			getSessionFile: () => parentFile,
			getLeafId: () => "leaf",
			getSessionDir: () => input.dir,
		},
		"fork",
		{ openSession: () => sourceManager },
	);
	return {
		resolver,
		counts: () => ({ creates, flushes, closes, compatibilityReads }),
	};
}

const rssChildLane = process.env.PI_SUBAGENTS_RSS_CHILD;

function maxResidentBytes(): number {
	const value = process.resourceUsage().maxRSS;
	return process.platform === "darwin" ? value : value * 1024;
}

if (rssChildLane === "tokens" || rssChildLane === "fork") {
	test(`large ${rssChildLane} scan stays below the RSS ceiling`, () => {
		const requestedBytes = Number.parseInt(
			process.env.PI_SUBAGENTS_HISTORY_BYTES ?? "67108864",
			10,
		);
		const maxRssDelta = Number.parseInt(
			process.env.PI_SUBAGENTS_MAX_RSS_DELTA_BYTES ?? "32505856",
			10,
		);
		assert(
			Number.isSafeInteger(requestedBytes) && requestedBytes >= 8 * 1024 * 1024,
		);
		assert(
			Number.isSafeInteger(maxRssDelta) &&
				maxRssDelta > 0 &&
				maxRssDelta < requestedBytes / 2,
			"RSS ceiling must be positive and less than half the requested history size",
		);
		const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-rss-"));
		const branchFile = join(dir, "branch.jsonl");
		let expectedInput = 0;
		let expectedOutput = 0;
		let previousId: string | null = null;
		let historyBytes = 0;
		let leafId = "";
		const payload = "x".repeat(64 * 1024);
		const fd = realFs.openSync(branchFile, "wx");
		try {
			const header = `${JSON.stringify({ type: "session", version: 3, id: "large", timestamp: "2026-08-06T00:00:00.000Z" })}\n`;
			writeAll(fd, header);
			historyBytes += Buffer.byteLength(header);
			for (let index = 0; historyBytes < requestedBytes; index++) {
				leafId = `entry-${index}`;
				expectedInput += index + 1;
				expectedOutput += 2;
				const content =
					index === 0
						? [
								{
									type: "thinking",
									thinking: "private",
									thinkingSignature: "signed",
								},
								{ type: "text", text: payload },
							]
						: [{ type: "text", text: payload }];
				const line = `${JSON.stringify({
					type: "message",
					id: leafId,
					parentId: previousId,
					timestamp: "2026-08-06T00:00:00.000Z",
					message: {
						role: index === 0 ? "assistant" : "user",
						provider: index === 0 ? "anthropic" : undefined,
						content,
						usage: { inputTokens: index + 1, outputTokens: 2 },
					},
				})}\n`;
				writeAll(fd, line);
				historyBytes += Buffer.byteLength(line);
				previousId = leafId;
			}
			realFs.fsyncSync(fd);
		} finally {
			realFs.closeSync(fd);
		}

		const parentFile = join(dir, "parent", "session.jsonl");
		realFs.mkdirSync(join(dir, "parent"));
		realFs.writeFileSync(
			parentFile,
			'{"type":"session","version":3,"id":"parent"}\n',
		);
		const childCwd = join(dir, "child-cwd");
		const childCwdLink = join(dir, "child-cwd-link");
		realFs.mkdirSync(childCwd);
		realFs.symlinkSync(childCwd, childCwdLink);
		const warmDir = join(dir, "warm");
		realFs.mkdirSync(warmDir);
		const warmFile = join(warmDir, "session.jsonl");
		realFs.writeFileSync(
			warmFile,
			encodeJsonl([
				{ type: "session", version: 3, id: "warm" },
				{
					type: "message",
					id: "warm-assistant",
					message: {
						role: "assistant",
						provider: "anthropic",
						content: [{ type: "thinking", thinkingSignature: "signed" }],
						usage: { inputTokens: 1, outputTokens: 1 },
					},
				},
			]),
		);
		if (rssChildLane === "tokens") {
			expect(parseSessionTokens(warmDir)).toEqual({
				input: 1,
				output: 1,
				total: 2,
			});
		} else {
			expect(sanitizePersistedFork(warmFile, true)).toBe("off");
		}
		realFs.rmSync(warmDir, { recursive: true, force: true });
		Bun.gc(true);
		const before = maxResidentBytes();
		try {
			if (rssChildLane === "tokens") {
				expect(parseSessionTokens(dir)).toEqual({
					input: expectedInput,
					output: expectedOutput,
					total: expectedInput + expectedOutput,
				});
			} else {
				const resolver = createForkContextResolver(
					{
						getSessionFile: () => parentFile,
						getLeafId: () => leafId,
						getSessionDir: () => dir,
					},
					"fork",
					{
						openSession: () => ({
							createBranchedSession: () => branchFile,
							close() {},
						}),
					},
				);
				expect(resolver.sessionFileForIndex()).toBe(branchFile);
				expect(resolver.thinkingOverrideForIndex()).toBe("off");
				if (expectsForkCwdAlignment) {
					expect(typeof alignForkedSessionCwd).toBe("function");
					alignForkedSessionCwd(branchFile, childCwdLink);
				}
			}
			const rssDeltaBytes = Math.max(0, maxResidentBytes() - before);
			expect(rssDeltaBytes).toBeLessThan(maxRssDelta);

			if (rssChildLane === "fork") {
				const headFd = realFs.openSync(branchFile, "r");
				try {
					const head = Buffer.alloc(128 * 1024);
					const bytes = realFs.readSync(headFd, head, 0, head.length, 0);
					const text = head.subarray(0, bytes).toString("utf-8");
					const header = JSON.parse(text.split("\n", 1)[0]);
					if (expectsForkCwdAlignment) {
						expect(header.cwd).toBe(realFs.realpathSync.native(childCwd));
					}
					expect(text).not.toContain("thinkingSignature");
					expect(text).toContain(payload.slice(0, 1024));
				} finally {
					realFs.closeSync(headFd);
				}
				const tailFd = realFs.openSync(branchFile, "r");
				try {
					const size = realFs.fstatSync(tailFd).size;
					const tail = Buffer.alloc(Math.min(4096, size));
					const bytes = realFs.readSync(
						tailFd,
						tail,
						0,
						tail.length,
						size - tail.length,
					);
					const last = tail
						.subarray(0, bytes)
						.toString("utf-8")
						.trim()
						.split("\n")
						.at(-1);
					assert(last);
					expect(JSON.parse(last)).toMatchObject({
						type: "thinking_level_change",
						parentId: leafId,
						thinkingLevel: "off",
					});
				} finally {
					realFs.closeSync(tailFd);
				}
			}
			console.log(
				`PI_SUBAGENTS_RSS=${JSON.stringify({ lane: rssChildLane, historyBytes, rssDeltaBytes, maxRssDelta })}`,
			);
		} finally {
			realFs.rmSync(dir, { recursive: true, force: true });
		}
	}, 120_000);
} else {
	describe("pi-subagents bounded session history", () => {
		test("persists and sanitizes the exact fork without compatibility reads", () => {
			const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-fork-"));
			try {
				const branchFile = join(dir, "branch.jsonl");
				const header = {
					type: "session",
					version: 3,
					id: "fork",
					timestamp: "t0",
				};
				const assistant = {
					type: "message",
					id: "assistant",
					parentId: null,
					timestamp: "t1",
					message: {
						role: "assistant",
						provider: "anthropic",
						content: [
							{ type: "text", text: "kept" },
							{
								type: "thinking",
								thinking: "private",
								thinkingSignature: "signed",
							},
							{ type: "redacted_thinking", data: "redacted" },
						],
					},
				};
				const user = {
					type: "message",
					id: "user",
					parentId: "assistant",
					timestamp: "t2",
					message: { role: "user", content: [{ type: "text", text: "next" }] },
				};
				const label = {
					type: "label",
					id: "label",
					parentId: "user",
					timestamp: "t3",
					targetId: "user",
					label: "chosen",
				};
				const harness = forkHarness({
					dir,
					branchFile,
					branchBytes: encodeJsonl([header, assistant, user, label]),
					deferPersistence: true,
				});

				expect(harness.resolver.sessionFileForIndex(4)).toBe(branchFile);
				expect(harness.resolver.thinkingOverrideForIndex(4)).toBe("off");
				expect(harness.resolver.sessionFileForIndex(4)).toBe(branchFile);
				expect(harness.counts()).toEqual({
					creates: 1,
					flushes: 1,
					closes: 1,
					compatibilityReads: 0,
				});
				const entries = decodeJsonl(branchFile);
				expect(entries.slice(0, 4).map((entry) => entry.id)).toEqual([
					"fork",
					"assistant",
					"user",
					"label",
				]);
				expect(entries[0]).toEqual(header);
				expect((entries[1] as typeof assistant).message.content).toEqual([
					{ type: "text", text: "kept" },
				]);
				expect(entries[2]).toEqual(user);
				expect(entries[3]).toEqual(label);
				expect(entries[4]).toMatchObject({
					type: "thinking_level_change",
					parentId: "label",
					thinkingLevel: "off",
				});
				expect(tempFiles(dir, branchFile)).toEqual([]);
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("aligns cwd atomically without sanitizing signed thinking", () => {
			if (!expectsForkCwdAlignment) return;
			const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-cwd-"));
			try {
				const branchFile = join(dir, "branch.jsonl");
				const childCwd = join(dir, "child-cwd");
				realFs.mkdirSync(childCwd);
				realFs.writeFileSync(
					branchFile,
					encodeJsonl([
						{ type: "session", version: 3, id: "fork", cwd: "/parent" },
						{
							type: "message",
							id: "assistant",
							message: {
								role: "assistant",
								provider: "anthropic",
								content: [{ type: "thinking", thinkingSignature: "signed" }],
							},
						},
					]),
				);

				expect(typeof alignForkedSessionCwd).toBe("function");
				alignForkedSessionCwd(branchFile, childCwd);
				const entries = decodeJsonl(branchFile);
				expect(entries[0].cwd).toBe(realFs.realpathSync.native(childCwd));
				expect(entries[1]).toMatchObject({
					message: {
						content: [{ type: "thinking", thinkingSignature: "signed" }],
					},
				});
				expect(tempFiles(dir, branchFile)).toEqual([]);
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("fails closed on malformed JSONL without changing the persisted branch", () => {
			const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-malformed-"));
			try {
				const branchFile = join(dir, "branch.jsonl");
				const source = Buffer.from(
					[
						JSON.stringify({ type: "session", version: 3, id: "fork" }),
						JSON.stringify({
							type: "message",
							id: "assistant",
							parentId: null,
							message: {
								role: "assistant",
								provider: "anthropic",
								content: [{ type: "thinking", thinkingSignature: "signed" }],
							},
						}),
						"{malformed",
						"",
					].join("\n"),
				);
				const harness = forkHarness({ dir, branchFile, branchBytes: source });
				expect(() => harness.resolver.sessionFileForIndex()).toThrow(
					/invalid JSONL on line 3/,
				);
				expect(realFs.readFileSync(branchFile)).toEqual(source);
				expect(tempFiles(dir, branchFile)).toEqual([]);
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("keeps source bytes when atomic replacement fails", () => {
			const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-rename-"));
			try {
				const branchFile = join(dir, "branch.jsonl");
				const source = encodeJsonl(
					[
						{ type: "session", version: 3, id: "fork" },
						{
							type: "message",
							id: "assistant",
							parentId: null,
							message: {
								role: "assistant",
								provider: "anthropic",
								content: [{ type: "thinking", thinkingSignature: "signed" }],
							},
						},
					],
					false,
				);
				realFs.writeFileSync(branchFile, source);
				expect(() =>
					sanitizePersistedFork(branchFile, true, {
						renameSync() {
							throw new Error("injected atomic rename failure");
						},
					}),
				).toThrow(/injected atomic rename failure/);
				expect(realFs.readFileSync(branchFile)).toEqual(source);
				expect(tempFiles(dir, branchFile)).toEqual([]);

				let writeCalls = 0;
				expect(() =>
					sanitizePersistedFork(branchFile, true, {
						writeSync(
							fd: number,
							bytes: Uint8Array,
							offset: number,
							length: number,
						) {
							writeCalls++;
							if (writeCalls === 3)
								throw new Error("injected replacement write failure");
							return realFs.writeSync(fd, bytes, offset, Math.min(length, 7));
						},
					}),
				).toThrow(/injected replacement write failure/);
				expect(realFs.readFileSync(branchFile)).toEqual(source);
				expect(tempFiles(dir, branchFile)).toEqual([]);
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("retries short writes until the replacement is complete", () => {
			const dir = realFs.mkdtempSync(
				join(tmpdir(), "pi-subagents-short-write-"),
			);
			try {
				const branchFile = join(dir, "branch.jsonl");
				const source = encodeJsonl(
					[
						{ type: "session", version: 3, id: "fork" },
						{
							type: "message",
							id: "assistant",
							parentId: null,
							message: {
								role: "assistant",
								provider: "anthropic",
								content: [
									{ type: "text", text: "kept" },
									{ type: "thinking", thinkingSignature: "signed" },
								],
							},
						},
					],
					false,
				);
				realFs.writeFileSync(branchFile, source);
				realFs.chmodSync(branchFile, 0o640);
				let writes = 0;
				expect(
					sanitizePersistedFork(branchFile, true, {
						writeSync(
							fd: number,
							bytes: Uint8Array,
							offset: number,
							length: number,
						) {
							writes++;
							return realFs.writeSync(fd, bytes, offset, Math.min(length, 7));
						},
					}),
				).toBe("off");
				expect(writes).toBeGreaterThan(4);
				const entries = decodeJsonl(branchFile);
				expect(entries).toHaveLength(3);
				expect(entries[1]).toMatchObject({
					id: "assistant",
					message: { content: [{ type: "text", text: "kept" }] },
				});
				expect(entries[2]).toMatchObject({
					type: "thinking_level_change",
					parentId: "assistant",
					thinkingLevel: "off",
				});
				expect(realFs.statSync(branchFile).mode & 0o777).toBe(0o640);
				expect(tempFiles(dir, branchFile)).toEqual([]);
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("streams token usage and preserves best-effort malformed-tail behavior", () => {
			const dir = realFs.mkdtempSync(join(tmpdir(), "pi-subagents-tokens-"));
			try {
				realFs.writeFileSync(
					join(dir, "session.jsonl"),
					[
						JSON.stringify({ type: "session", version: 3, id: "tokens" }),
						JSON.stringify({ usage: { inputTokens: 2, outputTokens: 3 } }),
						"{malformed}",
						"",
						JSON.stringify({ message: { usage: { input: 5, output: 7 } } }),
					].join("\n"),
				);
				expect(parseSessionTokens(dir)).toEqual({
					input: 7,
					output: 10,
					total: 17,
				});
			} finally {
				realFs.rmSync(dir, { recursive: true, force: true });
			}
		});

		test("contains no compatibility rewrite and delegates background HTML streaming to core", () => {
			const forkSource = realFs.readFileSync(
				join(packageRoot, "src/shared/fork-context.ts"),
				"utf-8",
			);
			const extensionSource = realFs.readFileSync(
				join(packageRoot, "src/extension/index.ts"),
				"utf-8",
			);
			const tokenSource = realFs.readFileSync(
				join(packageRoot, "src/shared/session-tokens.ts"),
				"utf-8",
			);
			const slashSource = realFs.readFileSync(
				join(packageRoot, "src/slash/slash-commands.ts"),
				"utf-8",
			);
			const backgroundSource = realFs.readFileSync(
				join(packageRoot, "src/runs/background/subagent-runner.ts"),
				"utf-8",
			);
			for (const forbidden of [
				"getEntries",
				"readFileSync",
				'.split("\\n")',
				"writeFileSync",
			]) {
				expect(forkSource).not.toContain(forbidden);
			}
			for (const forbidden of ["readFileSync", '.split("\\n")']) {
				expect(tokenSource).not.toContain(forbidden);
			}
			expect(extensionSource).toContain(
				"restoreSlashFinalSnapshots(ctx.sessionManager.getRecentActiveEntries({",
			);
			expect(extensionSource).toContain("customType: SLASH_RESULT_TYPE");
			expect(extensionSource).toContain("limit: 256");
			expect(extensionSource).not.toContain(
				"restoreSlashFinalSnapshots(ctx.sessionManager.getEntries())",
			);
			expect(slashSource).not.toContain("_rewriteFile");
			expect(slashSource).toContain("sessionManager.flush()");
			expect(slashSource).toContain(
				"sessionManager.iterateBranchEntries((entry) =>",
			);
			expect(slashSource).not.toContain(
				"sessionManager.iterateEntries({}, (entry) =>",
			);
			const exportStart = backgroundSource.indexOf(
				"async function exportSessionHtml",
			);
			const exportEnd = backgroundSource.indexOf(
				"function createShareLink",
				exportStart,
			);
			expect(exportStart).toBeGreaterThanOrEqual(0);
			expect(exportEnd).toBeGreaterThan(exportStart);
			const exportSource = backgroundSource.slice(exportStart, exportEnd);
			expect(exportSource).toContain(
				"exportFromFile(sessionFile, { outputPath })",
			);
			expect(exportSource).not.toContain("getEntries");
			expect(exportSource).not.toContain("readFileSync");
			expect(backgroundSource).toContain(
				"const htmlPath = await exportSessionHtml(sessionFile, exportDir, config.piPackageRoot)",
			);
		});

		test("isolated large-history children prove bounded RSS", () => {
			for (const lane of ["tokens", "fork"] as const) {
				const result = Bun.spawnSync({
					cmd: [process.execPath, "test", import.meta.path],
					env: { ...process.env, PI_SUBAGENTS_RSS_CHILD: lane },
					stdout: "pipe",
					stderr: "pipe",
				});
				const stdout = result.stdout.toString();
				const stderr = result.stderr.toString();
				expect(result.exitCode, `${lane}:\n${stdout}\n${stderr}`).toBe(0);
				const reportJson = stdout.match(/PI_SUBAGENTS_RSS=(\{[^\n]+\})/)?.[1];
				assert(reportJson, stdout);
				const report = JSON.parse(reportJson) as {
					lane: string;
					historyBytes: number;
					rssDeltaBytes: number;
					maxRssDelta: number;
				};
				expect(report.lane).toBe(lane);
				expect(report.historyBytes).toBeGreaterThanOrEqual(
					Number.parseInt(
						process.env.PI_SUBAGENTS_HISTORY_BYTES ?? "67108864",
						10,
					),
				);
				expect(report.rssDeltaBytes).toBeLessThan(report.maxRssDelta);
				console.log(`PI_SUBAGENTS_RSS_PARENT=${JSON.stringify(report)}`);
			}
		}, 180_000);
	});
}
