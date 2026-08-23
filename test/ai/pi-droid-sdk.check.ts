import { expect, mock, test } from "bun:test";

const authQueries: Array<[unknown, unknown]> = [];

mock.module("@earendil-works/pi-coding-agent", () => ({
	AuthStorage: {
		create: () => ({
			getApiKey: async (provider: unknown, options: unknown) => {
				authQueries.push([provider, options]);
				return undefined;
			},
		}),
	},
}));
mock.module("@earendil-works/pi-ai", () => ({
	createAssistantMessageEventStream: () => {
		throw new Error("streaming is outside the credential-free load test");
	},
}));
mock.module("@earendil-works/pi-tui", () => ({
	Text: class Text {},
}));
mock.module("typebox", () => ({
	Type: new Proxy({}, {
		get: () => (...args: unknown[]) => ({ args }),
	}),
}));

const root = process.env.PI_DROID_SDK_ROOT;
if (!root) throw new Error("PI_DROID_SDK_ROOT is required");
const expectedExecPath = process.env.PI_DROID_EXPECTED_EXEC_PATH;
if (!expectedExecPath) throw new Error("PI_DROID_EXPECTED_EXEC_PATH is required");
delete process.env.FACTORY_API_KEY;
process.env.PI_DROID_AUTONOMY_LEVEL = "off";
process.env.PI_DROID_PI_TOOL_BRIDGE = "0";

const factorySdk = await import(`${root}/node_modules/@factory/droid-sdk/dist/index.js`);
let createSessionCalls = 0;
mock.module("@factory/droid-sdk", () => ({
	...factorySdk,
	createSession: (..._args: unknown[]) => {
		createSessionCalls += 1;
		throw new Error("Droid startup is outside the credential-free load test");
	},
}));

const [
	{ default: registerDroid },
	{ buildDroidProcessEnv, getDroidExecPath },
	{ resolveFactoryApiKey },
	{ handleDroidPermissionRequest, resolveDroidAutonomyLevel },
	{ resolveDroidPiToolBridgeEnabled },
] = await Promise.all([
	import(`${root}/src/index.ts`),
	import(`${root}/src/droid-process-env.ts`),
	import(`${root}/src/droid-provider.ts`),
	import(`${root}/src/droid-permissions.ts`),
	import(`${root}/src/droid-pi-tool-bridge.ts`),
]);
const { AutonomyLevel, ToolConfirmationOutcome, ToolConfirmationType } = factorySdk;

type Provider = {
	name?: unknown;
	baseUrl?: unknown;
	apiKey?: unknown;
	api?: unknown;
	models?: Array<Record<string, unknown>>;
};

test("loads the pinned Factory provider without credentials or Droid startup", async () => {
	const providers = new Map<string, Provider>();
	const commands = new Set<string>();
	const tools = new Set<string>();
	let activeTools: string[] = [];
	const originalArgvLength = process.argv.length;
	process.argv.push("--api-key=cross-provider-decoy");
	try {
		await registerDroid({
			registerProvider(id: string, provider: Provider) {
				providers.set(id, provider);
			},
			registerCommand(name: string) {
				commands.add(name);
			},
			registerTool(tool: { name: string }) {
				tools.add(tool.name);
			},
			on() {},
			getActiveTools: () => activeTools,
			getAllTools: () => [],
			setActiveTools(next: string[]) {
				activeTools = [...next];
			},
		} as never);
	} finally {
		process.argv.length = originalArgvLength;
	}

	const provider = providers.get("factory");
	expect(provider).toBeDefined();
	expect(provider?.name).toBe("Factory");
	expect(provider?.baseUrl).toBe("https://factory.ai");
	expect(provider?.apiKey).toBe("FACTORY_API_KEY");
	expect(provider?.api).toBe("droid-sdk");
	expect(provider?.models).toHaveLength(26);
	expect(authQueries).toEqual([["factory", { includeFallback: false }]]);

	const models = provider?.models ?? [];
	const ids = models.map((model) => model.id);
	expect(new Set(ids).size).toBe(ids.length);
	expect(ids).toContain("claude-opus-4-7");
	expect(ids).toContain("gpt-5.5");
	expect(ids).toContain("kimi-k2.5");
	expect(models.every((model) => model.api === "droid-sdk")).toBe(true);
	expect(models.find((model) => model.id === "gpt-5.5")?.reasoning).toBe(true);
	expect(commands).toContain("droid-refresh-models");
	expect(tools).not.toContain("droid_ask_question");
	expect(activeTools).toEqual([]);
	expect(createSessionCalls).toBe(0);
});

test("passes only the managed Droid process environment", () => {
	expect(getDroidExecPath()).toBe(expectedExecPath);
	const childEnv = buildDroidProcessEnv("resolved-factory-key", {
		ANTHROPIC_API_KEY: "blocked",
		AWS_SECRET_ACCESS_KEY: "blocked",
		BASH_ENV: "blocked",
		DYLD_INSERT_LIBRARIES: "blocked",
		FACTORY_API_KEY: "ambient-factory-key",
		FACTORY_AUTO_UPDATE: "false",
		GH_TOKEN: "blocked",
		GNUPGHOME: "blocked",
		HOME: "/home/test",
		HTTPS_PROXY: "https://proxy.invalid",
		LANGUAGE: "en",
		LC_MESSAGES: "C",
		LD_PRELOAD: "blocked",
		NODE_OPTIONS: "blocked",
		OMLX_API_KEY: "blocked",
		OPENAI_API_KEY: "blocked",
		PATH: "/managed/bin",
		PI_DROID_PI_TOOL_BRIDGE: "1",
		SSH_AUTH_SOCK: "blocked",
		SSL_CERT_DIR: "/certs",
		SSL_CERT_FILE: "/certs/ca.pem",
		TMPDIR: "/tmp/test",
		XDG_CONFIG_HOME: "/config",
	});
	expect(Object.keys(childEnv).sort()).toEqual([
		"FACTORY_API_KEY",
		"FACTORY_AUTO_UPDATE",
		"HOME",
		"HTTPS_PROXY",
		"LANGUAGE",
		"LC_MESSAGES",
		"PATH",
		"SSL_CERT_DIR",
		"SSL_CERT_FILE",
		"TMPDIR",
		"XDG_CONFIG_HOME",
	]);
	expect(childEnv.FACTORY_API_KEY).toBe("resolved-factory-key");
});

test("rejects unscoped keys and fails closed on Droid permissions", async () => {
	process.env.FACTORY_API_KEY = "factory-env-decoy";
	try {
		expect(resolveFactoryApiKey("cross-provider-decoy")).toBeUndefined();
		expect(resolveFactoryApiKey("FACTORY_API_KEY")).toBe("factory-env-decoy");
	} finally {
		delete process.env.FACTORY_API_KEY;
	}

	for (const value of [undefined, "", "invalid"]) {
		if (value === undefined) delete process.env.PI_DROID_AUTONOMY_LEVEL;
		else process.env.PI_DROID_AUTONOMY_LEVEL = value;
		expect(resolveDroidAutonomyLevel()).toBe(AutonomyLevel.Off);
		expect(resolveDroidPiToolBridgeEnabled({ PI_DROID_PI_TOOL_BRIDGE: value })).toBe(false);
	}
	delete process.env.PI_DROID_AUTONOMY_LEVEL;

	const nativeMcp = {
		toolUses: [{ details: { type: ToolConfirmationType.McpTool }, toolName: "native_mcp" }],
	};
	const piBridgeName = {
		toolUses: [{ details: { type: ToolConfirmationType.McpTool }, toolName: "pi__read" }],
	};
	const mixed = {
		toolUses: [
			{ details: { type: ToolConfirmationType.McpTool }, toolName: "pi__read" },
			{ details: { type: ToolConfirmationType.Execute, command: "true" }, toolName: "execute" },
		],
	};
	for (const request of [nativeMcp, piBridgeName, mixed]) {
		expect(await handleDroidPermissionRequest(request as never)).toBe(ToolConfirmationOutcome.Cancel);
	}
});
