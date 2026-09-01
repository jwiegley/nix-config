import { expect, mock, test } from "bun:test";
import { unlink, writeFile } from "node:fs/promises";

const authQueries: unknown[] = [];
let useStoredFactoryCredential = false;
let assistantStreamEvents: Array<Record<string, unknown>> = [];
let assistantStreamFinished: Promise<void> | undefined;
let finishAssistantStream: (() => void) | undefined;

const piCodingAgentRoot = process.env.PI_CODING_AGENT_ROOT;
if (!piCodingAgentRoot) throw new Error("PI_CODING_AGENT_ROOT is required");
const piCodingAgentDir = process.env.PI_CODING_AGENT_DIR;
if (!piCodingAgentDir) throw new Error("PI_CODING_AGENT_DIR is required");
const actualPiCodingAgent = await import(`${piCodingAgentRoot}/dist/index.js`);
if (typeof actualPiCodingAgent.readStoredCredential !== "function") {
	throw new Error("Pi must export readStoredCredential");
}

mock.module("@earendil-works/pi-coding-agent", () => ({
	readStoredCredential: (provider: unknown) => {
		authQueries.push(provider);
		return useStoredFactoryCredential
			? actualPiCodingAgent.readStoredCredential(String(provider))
			: undefined;
	},
}));
mock.module("@earendil-works/pi-ai", () => ({
	createAssistantMessageEventStream: () => {
		assistantStreamEvents = [];
		assistantStreamFinished = new Promise((resolve) => {
			finishAssistantStream = resolve;
		});
		return {
			push(event: Record<string, unknown>) {
				assistantStreamEvents.push(event);
			},
			end() {
				finishAssistantStream?.();
			},
		};
	},
}));
mock.module("@earendil-works/pi-tui", () => ({
	Text: class Text {},
}));
mock.module("typebox", () => ({
	Type: new Proxy(
		{},
		{
			get:
				() =>
				(...args: unknown[]) => ({ args }),
		},
	),
}));

const root = process.env.PI_DROID_SDK_ROOT;
if (!root) throw new Error("PI_DROID_SDK_ROOT is required");
const expectedExecPath = process.env.PI_DROID_EXPECTED_EXEC_PATH;
if (!expectedExecPath)
	throw new Error("PI_DROID_EXPECTED_EXEC_PATH is required");
delete process.env.FACTORY_API_KEY;
process.env.PI_DROID_AUTONOMY_LEVEL = "off";
process.env.PI_DROID_PI_TOOL_BRIDGE = "0";

const factorySdk = await import(
	`${root}/node_modules/@factory/droid-sdk/dist/index.js`
);
let createSessionCalls = 0;
let createSessionOptions: Record<string, unknown> | undefined;
let discoverySession: Record<string, unknown> | undefined;
let nodeSdkLoads = 0;
let listModelsCalls = 0;
let listModelsOptions: Record<string, unknown> | undefined;
let liveModels: unknown[] | undefined;
let streamOptions: Record<string, unknown> | undefined;
mock.module("@factory/droid-sdk", () => factorySdk);
mock.module("@factory/droid-sdk/node", () => {
	nodeSdkLoads += 1;
	return {
		createSession: (options: Record<string, unknown>) => {
			createSessionCalls += 1;
			createSessionOptions = options;
			if (discoverySession) return discoverySession;
			throw new Error("Droid startup is outside the credential-free load test");
		},
		listModels: async (options: Record<string, unknown>) => {
			listModelsCalls += 1;
			listModelsOptions = options;
			if (liveModels) return liveModels;
			throw new Error("Droid discovery is outside the credential-free load test");
		},
	};
});

const [
	{ default: registerDroid },
	{ buildDroidProcessEnv, getDroidExecPath },
	{ resolveFactoryApiKey, streamDroid },
	{ handleDroidPermissionRequest, resolveDroidAutonomyLevel },
	{ resolveDroidPiToolBridgeEnabled },
	{ discoverModels, getDiscoveryApiKey },
] = await Promise.all([
	import(`${root}/src/index.ts`),
	import(`${root}/src/droid-process-env.ts`),
	import(`${root}/src/droid-provider.ts`),
	import(`${root}/src/droid-permissions.ts`),
	import(`${root}/src/droid-pi-tool-bridge.ts`),
	import(`${root}/src/model-discovery.ts`),
]);
const { AutonomyLevel, ToolConfirmationOutcome, ToolConfirmationType } =
	factorySdk;
const factoryLiveModel = factorySdk.ModelInfoSchema.parse({
	id: "gpt-5.6-sol",
	displayName: "GPT-5.6 Sol",
	shortDisplayName: "GPT-5.6 Sol",
	modelProvider: factorySdk.ModelProvider.FACTORY,
	supportedReasoningEfforts: [
		factorySdk.ReasoningEffort.None,
		factorySdk.ReasoningEffort.Low,
		factorySdk.ReasoningEffort.Medium,
		factorySdk.ReasoningEffort.High,
		factorySdk.ReasoningEffort.ExtraHigh,
		factorySdk.ReasoningEffort.Max,
	],
	defaultReasoningEffort: factorySdk.ReasoningEffort.Medium,
});

type Provider = {
	name?: unknown;
	baseUrl?: unknown;
	apiKey?: unknown;
	api?: unknown;
	models?: Array<Record<string, unknown>>;
};

test("uses the bundled Factory catalog until explicit refresh", async () => {
	const providers = new Map<string, Provider>();
	const commands = new Set<string>();
	const tools = new Set<string>();
	let activeTools: string[] = [];
	let refreshModels: unknown;
	const extensionApi = () => ({
		registerProvider(id: string, provider: Provider) {
			providers.set(id, provider);
		},
		registerCommand(name: string, options: { handler: unknown }) {
			commands.add(name);
			if (name === "droid-refresh-models") refreshModels = options.handler;
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
	}) as never;
	const originalArgvLength = process.argv.length;
	process.argv.push("--api-key=cross-provider-decoy");
	try {
		await registerDroid(extensionApi());
		await registerDroid(extensionApi());
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
	expect(authQueries).toEqual([]);

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
	expect(listModelsCalls).toBe(0);
	expect(nodeSdkLoads).toBe(0);
	expect(refreshModels).toBeFunction();
	await (
		refreshModels as (args: string, ctx: { hasUI: boolean }) => Promise<void>
	)("", { hasUI: false });
	expect(authQueries).toEqual(["factory"]);
	expect(listModelsCalls).toBe(0);
	expect(nodeSdkLoads).toBe(0);
});

test("reads stored Factory auth through the current Pi credential API", async () => {
	const authPath = `${piCodingAgentDir}/auth.json`;
	let closeCalls = 0;
	await writeFile(
		authPath,
		JSON.stringify({
			factory: { type: "api_key", key: "stored-factory-key" },
		}),
		{ flag: "wx", mode: 0o600 },
	);
	useStoredFactoryCredential = true;
	liveModels = [factoryLiveModel];
	try {
		expect(await getDiscoveryApiKey()).toBe("stored-factory-key");
		expect(await resolveFactoryApiKey("stored-factory-key")).toBe(
			"stored-factory-key",
		);
		expect(
			await resolveFactoryApiKey("cross-provider-decoy"),
		).toBeUndefined();
		const models = await discoverModels();
		expect(models.map((model) => model.id)).toEqual(["gpt-5.6-sol"]);
		expect(nodeSdkLoads).toBe(1);
		const requestModel = models[0];
		if (!requestModel) throw new Error("Factory discovery returned no model");
		expect(listModelsOptions?.apiKey).toBe("stored-factory-key");
		expect(listModelsOptions?.execPath).toBe(expectedExecPath);
		expect(listModelsOptions?.env).toEqual(
			buildDroidProcessEnv("stored-factory-key", process.env),
		);

		discoverySession = {
			async *stream(_prompt: unknown, options: Record<string, unknown>) {
				streamOptions = options;
				yield {
					type: factorySdk.DroidMessageType.Result,
					subtype: "success",
					success: true,
					interrupted: false,
					error: null,
					tokenUsage: null,
				};
			},
			close: async () => {
				closeCalls += 1;
			},
		};
		createSessionOptions = undefined;
		streamOptions = undefined;
		streamDroid(
			{
				...requestModel,
				provider: "factory",
				baseUrl: "https://factory.ai",
			},
			{
				systemPrompt: "Factory request auth test",
				messages: [{ role: "user", content: "test", timestamp: 0 }],
			},
			{ apiKey: "stored-factory-key", reasoning: "off" },
		);
		if (!assistantStreamFinished) throw new Error("Factory stream did not start");
		await assistantStreamFinished;
		expect(createSessionOptions?.apiKey).toBe("stored-factory-key");
		expect(createSessionOptions?.reasoningEffort).toBe(
			factorySdk.ReasoningEffort.None,
		);
		expect(createSessionOptions?.execPath).toBe(expectedExecPath);
		expect(createSessionOptions?.env).toEqual(
			buildDroidProcessEnv("stored-factory-key", process.env),
		);
		expect(streamOptions?.includePartialMessages).toBe(true);
		expect(assistantStreamEvents.map((event) => event.type)).toContain("done");
		expect(assistantStreamEvents.map((event) => event.type)).not.toContain(
			"error",
		);
		expect(closeCalls).toBe(1);
	} finally {
		discoverySession = undefined;
		liveModels = undefined;
		listModelsOptions = undefined;
		createSessionOptions = undefined;
		streamOptions = undefined;
		useStoredFactoryCredential = false;
		await unlink(authPath);
	}
	expect(authQueries.at(-1)).toBe("factory");
});

test("reads Factory auth from the environment for model discovery", async () => {
	const originalOmlxKey = process.env.OMLX_API_KEY;
	const originalSshAgent = process.env.SSH_AUTH_SOCK;
	process.env.FACTORY_API_KEY = "environment-factory-key";
	process.env.OMLX_API_KEY = "blocked-discovery-secret";
	process.env.SSH_AUTH_SOCK = "/blocked/agent.sock";
	liveModels = [factoryLiveModel];
	try {
		expect(await getDiscoveryApiKey()).toBe("environment-factory-key");
		const expectedDroidEnv = buildDroidProcessEnv(
			"environment-factory-key",
			process.env,
		);
		const models = await discoverModels();
		expect(models.map((model) => model.id)).toEqual(["gpt-5.6-sol"]);
		expect(listModelsOptions?.apiKey).toBe("environment-factory-key");
		expect(listModelsOptions?.execPath).toBe(expectedExecPath);
		expect(listModelsOptions?.env).toEqual(expectedDroidEnv);
	} finally {
		delete process.env.FACTORY_API_KEY;
		if (originalOmlxKey === undefined) delete process.env.OMLX_API_KEY;
		else process.env.OMLX_API_KEY = originalOmlxKey;
		if (originalSshAgent === undefined) delete process.env.SSH_AUTH_SOCK;
		else process.env.SSH_AUTH_SOCK = originalSshAgent;
		liveModels = undefined;
		listModelsOptions = undefined;
	}
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
		expect(
			await resolveFactoryApiKey("cross-provider-decoy"),
		).toBeUndefined();
		expect(await resolveFactoryApiKey("FACTORY_API_KEY")).toBe(
			"factory-env-decoy",
		);
	} finally {
		delete process.env.FACTORY_API_KEY;
	}

	for (const value of [undefined, "", "invalid"]) {
		if (value === undefined) delete process.env.PI_DROID_AUTONOMY_LEVEL;
		else process.env.PI_DROID_AUTONOMY_LEVEL = value;
		expect(resolveDroidAutonomyLevel()).toBe(AutonomyLevel.Off);
		expect(
			resolveDroidPiToolBridgeEnabled({ PI_DROID_PI_TOOL_BRIDGE: value }),
		).toBe(false);
	}
	delete process.env.PI_DROID_AUTONOMY_LEVEL;

	const nativeMcp = {
		toolUses: [
			{
				details: { type: ToolConfirmationType.McpTool },
				toolName: "native_mcp",
			},
		],
	};
	const piBridgeName = {
		toolUses: [
			{ details: { type: ToolConfirmationType.McpTool }, toolName: "pi__read" },
		],
	};
	const mixed = {
		toolUses: [
			{ details: { type: ToolConfirmationType.McpTool }, toolName: "pi__read" },
			{
				details: { type: ToolConfirmationType.Execute, command: "true" },
				toolName: "execute",
			},
		],
	};
	for (const request of [nativeMcp, piBridgeName, mixed]) {
		expect(await handleDroidPermissionRequest(request as never)).toBe(
			ToolConfirmationOutcome.Cancel,
		);
	}
});
