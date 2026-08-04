import { beforeEach, describe, expect, mock, test } from "bun:test";

const copied: string[] = [];
let copyFailure: Error | undefined;
let copyGate: Promise<void> | undefined;

mock.module("@earendil-works/pi-coding-agent", () => ({
	copyToClipboard: async (text: string) => {
		if (copyGate) await copyGate;
		if (copyFailure) throw copyFailure;
		copied.push(text);
	},
}));

mock.module("@earendil-works/pi-tui", () => ({
	matchesKey: () => false,
	truncateToWidth: (text: string) => text,
	visibleWidth: (text: string) => text.length,
	wrapTextWithAnsi: (text: string) => [text],
}));

const extensionPath = process.env.PI_COPY_MESSAGE_EXTENSION;
if (!extensionPath) throw new Error("PI_COPY_MESSAGE_EXTENSION is required");

const { default: registerCopyMessage } = await import(extensionPath);

type Command = {
	handler: (args: string, context: unknown) => Promise<void>;
};

const commands = new Map<string, Command>();
registerCopyMessage({
	registerCommand(name: string, command: Command) {
		commands.set(name, command);
	},
});

function context(notifications: Array<[string, string]>) {
	return {
		mode: "rpc",
		sessionManager: {
			getBranch: () => [
				{
					type: "message",
					id: "user-1",
					timestamp: "2026-08-04T12:00:00.000Z",
					message: { role: "user", content: [{ type: "text", text: "copy me" }] },
				},
			],
		},
		ui: {
			notify(message: string, level: string) {
				notifications.push([message, level]);
			},
		},
	};
}

beforeEach(() => {
	copied.length = 0;
	copyFailure = undefined;
	copyGate = undefined;
});

describe("Pi Copy Message clipboard integration", () => {
	test("awaits Pi's portable clipboard helper before reporting success", async () => {
		const notifications: Array<[string, string]> = [];
		let releaseCopy!: () => void;
		copyGate = new Promise((resolve) => {
			releaseCopy = resolve;
		});
		let completed = false;
		const pending = commands
			.get("copy-user")!
			.handler("", context(notifications))
			.then(() => {
				completed = true;
			});
		await Bun.sleep(0);

		expect(completed).toBe(false);
		expect(notifications).toEqual([]);

		releaseCopy();
		await pending;

		expect(copied).toEqual(["copy me"]);
		expect(notifications).toEqual([["Copied user message: “copy me”", "info"]]);
	});

	test("reports Pi clipboard failures without a false success", async () => {
		const notifications: Array<[string, string]> = [];
		copyFailure = new Error("portable clipboard unavailable");
		await commands.get("copy-user")!.handler("", context(notifications));

		expect(copied).toEqual([]);
		expect(notifications).toEqual([["portable clipboard unavailable", "error"]]);
	});

	test("copies through the latest and numbered copy-message selectors", async () => {
		for (const selector of ["latest", "1"]) {
			const notifications: Array<[string, string]> = [];
			await commands.get("copy-message")!.handler(selector, context(notifications));

			expect(copied.pop()).toBe("copy me");
			expect(notifications).toEqual([["Copied user message: “copy me”", "info"]]);
		}
	});
});
