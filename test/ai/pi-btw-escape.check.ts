import { describe, expect, mock, test } from "bun:test";

type TerminalResult = { consume?: boolean } | undefined;
type TerminalListener = (data: string) => TerminalResult;

class FakeContainer {
	addChild(_child: unknown): void {}
	clear(): void {}
}

class FakeInput {
	focused = false;
	onEscape?: () => void;
	onSubmit?: (value: string) => void;
	private value = "";

	getValue(): string {
		return this.value;
	}

	handleInput(_data: string): void {}

	setValue(value: string): void {
		this.value = value;
	}
}

class FakeText {
	constructor(public text: string) {}
	setText(text: string): void {
		this.text = text;
	}
}

mock.module("@earendil-works/pi-coding-agent", () => ({
	buildSessionContext: () => ({}),
	createAgentSession: async () => {
		throw new Error("BTW sub-session should not be created in this check");
	},
	createExtensionRuntime: () => ({}),
	SessionManager: { inMemory: () => ({}) },
}));

mock.module("@earendil-works/pi-tui", () => ({
	Box: FakeContainer,
	Container: FakeContainer,
	Input: FakeInput,
	Key: {
		alt: (key: string) => `alt+${key}`,
		ctrlAlt: (key: string) => `ctrl+alt+${key}`,
		down: "down",
		escape: "escape",
		pageDown: "pageDown",
		pageUp: "pageUp",
		up: "up",
	},
	matchesKey: (data: string, key: string) => key === "escape" && data === "\x1b",
	Text: FakeText,
	truncateToWidth: (text: string) => text,
	visibleWidth: (text: string) => text.length,
	wrapTextWithAnsi: (text: string) => [text],
}));

const extensionPath = process.env.PI_BTW_EXTENSION;
if (!extensionPath) throw new Error("PI_BTW_EXTENSION is required");

const { default: registerBtw } = await import(extensionPath);

function createHarness() {
	const commands = new Map<string, { handler: (args: string, ctx: unknown) => Promise<void> }>();
	const handlers = new Map<string, Array<(event: unknown, ctx: unknown) => Promise<void>>>();
	const listeners: Array<{ active: boolean; listener: TerminalListener }> = [];
	const handles: Array<{
		focused: boolean;
		hideCalls: number;
		focus: () => void;
		hide: () => void;
		isFocused: () => boolean;
		setHidden: (_hidden: boolean) => void;
		unfocus: () => void;
	}> = [];

	const ui = {
		custom: async (_factory: unknown, options: { onHandle?: (handle: unknown) => void }) => {
			const handle = {
				focused: false,
				hideCalls: 0,
				focus() {
					this.focused = true;
				},
				hide() {
					this.focused = false;
					this.hideCalls += 1;
				},
				isFocused() {
					return this.focused;
				},
				setHidden(_hidden: boolean) {},
				unfocus() {
					this.focused = false;
				},
			};
			handles.push(handle);
			options.onHandle?.(handle);
		},
		onTerminalInput(listener: TerminalListener) {
			const entry = { active: true, listener };
			listeners.push(entry);
			return () => {
				entry.active = false;
			};
		},
		setWidget() {},
	};
	const ctx = {
		getSystemPrompt: () => "",
		hasUI: true,
		isIdle: () => true,
		model: null,
		modelRegistry: { find: () => undefined },
		sessionManager: {
			getActiveContextEntries: () => [],
			getLatestCustomEntry: () => undefined,
			getLeafId: () => undefined,
			getRecentActiveEntries: () => [],
		},
		ui,
	};

	registerBtw({
		appendEntry() {},
		getThinkingLevel: () => "off",
		on(event: string, handler: (event: unknown, ctx: unknown) => Promise<void>) {
			const eventHandlers = handlers.get(event) ?? [];
			eventHandlers.push(handler);
			handlers.set(event, eventHandlers);
		},
		registerCommand(name: string, command: { handler: (args: string, ctx: unknown) => Promise<void> }) {
			commands.set(name, command);
		},
		registerMessageRenderer() {},
		registerShortcut() {},
	} as never);

	async function runEvent(name: string): Promise<void> {
		for (const handler of handlers.get(name) ?? []) await handler({}, ctx);
	}

	function addGoalListener(listener: TerminalListener): void {
		ui.onTerminalInput(listener);
	}

	function dispatch(data: string): TerminalResult {
		for (const entry of listeners) {
			if (!entry.active) continue;
			const result = entry.listener(data);
			if (result?.consume) return result;
		}
		return undefined;
	}

	return {
		addGoalListener,
		command: async (name: string) => commands.get(name)!.handler("", ctx),
		dispatch,
		handles,
		runEvent,
	};
}

describe("Pi BTW and Goal X Escape precedence", () => {
	test("closes a focused BTW overlay before Escape reaches Goal X", async () => {
		const harness = createHarness();
		let goalPauses = 0;

		await harness.runEvent("session_start");
		harness.addGoalListener(() => {
			goalPauses += 1;
			return { consume: true };
		});
		await harness.command("btw");

		expect(harness.handles.at(-1)?.isFocused()).toBe(true);
		expect(harness.dispatch("\x1b")).toEqual({ consume: true });
		expect(harness.handles.at(-1)?.hideCalls).toBe(1);
		expect(goalPauses).toBe(0);

		expect(harness.dispatch("\x1b")).toEqual({ consume: true });
		expect(goalPauses).toBe(1);
	});

	test("does not steal Escape while the BTW overlay is unfocused", async () => {
		const harness = createHarness();
		let goalPauses = 0;

		await harness.runEvent("session_start");
		harness.addGoalListener(() => {
			goalPauses += 1;
			return { consume: true };
		});
		await harness.command("btw");
		harness.handles.at(-1)?.unfocus();

		expect(harness.dispatch("\x1b")).toEqual({ consume: true });
		expect(harness.handles.at(-1)?.hideCalls).toBe(0);
		expect(goalPauses).toBe(1);
	});
});
