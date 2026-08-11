import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const source = process.argv[2];
assert.ok(source, "patched Pi source path is required");
const importFromSource = (relative) =>
	import(pathToFileURL(join(source, relative)));

const { DEFAULT_HTTP_IDLE_TIMEOUT_MS, createHttpIdleTimeoutFetch } =
	await importFromSource("dist/core/http-dispatcher.js");
assert.equal(DEFAULT_HTTP_IDLE_TIMEOUT_MS, 300_000);

const openSockets = new Set();
const server = createServer((request, response) => {
	response.writeHead(200, { "content-type": "text/plain" });
	response.write("ready");
	if (request.url !== "/stall") response.end();
});
server.on("connection", (socket) => {
	openSockets.add(socket);
	socket.on("close", () => openSockets.delete(socket));
});
await new Promise((resolve, reject) => {
	server.once("error", reject);
	server.listen(0, "127.0.0.1", resolve);
});
const address = server.address();
assert.ok(address && typeof address !== "string");

try {
	const idleTimeoutFetch = createHttpIdleTimeoutFetch(100);
	const responses = await Promise.all([
		idleTimeoutFetch(`http://127.0.0.1:${address.port}/one`),
		idleTimeoutFetch(`http://127.0.0.1:${address.port}/two`),
	]);
	assert.deepEqual(
		await Promise.all(responses.map((response) => response.text())),
		["ready", "ready"],
	);

	const stalled = await idleTimeoutFetch(
		`http://127.0.0.1:${address.port}/stall`,
	);
	await assert.rejects(
		stalled.text(),
		(error) =>
			error instanceof TypeError &&
			error.cause?.code === "UND_ERR_BODY_TIMEOUT",
	);

	const deadline = Date.now() + 2_000;
	while (openSockets.size > 0 && Date.now() < deadline) {
		await new Promise((resolve) => setTimeout(resolve, 10));
	}
	assert.equal(
		openSockets.size,
		0,
		"request-owned dispatchers must release their sockets",
	);
} finally {
	for (const socket of openSockets) socket.destroy();
	await new Promise((resolve) => server.close(resolve));
}

const provider = "transport-capability";
const modelId = "slow-model";
const root = await mkdtemp(join(tmpdir(), "pi-provider-transport-"));
const agentDir = join(root, "agent");
await mkdir(agentDir, { recursive: true });
const modelsPath = join(agentDir, "models.json");
await writeFile(
	modelsPath,
	JSON.stringify({
		providers: {
			[provider]: {
				api: "openai-completions",
				apiKey: "test-key",
				baseUrl: "http://127.0.0.1:1/v1",
				transport: {
					requestTimeoutMs: 7_200_000,
					idleTimeoutMs: 7_200_000,
				},
				models: [{ id: modelId }],
			},
		},
	}),
);

const { ModelConfig } = await importFromSource("dist/core/model-config.js");
const invalidModelsPath = join(root, "invalid-models.json");
for (const field of ["requestTimeoutMs", "idleTimeoutMs"]) {
	await writeFile(
		invalidModelsPath,
		JSON.stringify({
			providers: { invalid: { transport: { [field]: 2_147_483_648 } } },
		}),
	);
	const invalidConfig = await ModelConfig.load(invalidModelsPath);
	assert.match(invalidConfig.getError(), new RegExp(field));
	assert.match(invalidConfig.getError(), /2147483647/);
}

const { ModelRuntime } = await importFromSource("dist/core/model-runtime.js");
const runtime = await ModelRuntime.create({
	modelsPath,
	allowModelNetwork: false,
});
assert.equal(runtime.getError(), undefined);

const transport = runtime.getProviderTransportOptions(provider);
assert.equal(transport.timeoutMs, 7_200_000);
assert.equal(typeof transport.fetch, "function");
assert.notEqual(transport.fetch, globalThis.fetch);
assert.deepEqual(runtime.getProviderTransportOptions("ordinary-provider"), {});

let captured;
const { createAssistantMessageEventStream } = await importFromSource(
	"node_modules/@earendil-works/pi-ai/dist/index.js",
);
runtime.registerProvider(provider, {
	api: "openai-completions",
	streamSimple: (model, _context, options) => {
		captured = options;
		const stream = createAssistantMessageEventStream();
		stream.end({
			role: "assistant",
			content: [{ type: "text", text: "ok" }],
			api: model.api,
			provider: model.provider,
			model: model.id,
			usage: {
				input: 0,
				output: 0,
				cacheRead: 0,
				cacheWrite: 0,
				totalTokens: 0,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
			},
			stopReason: "stop",
			timestamp: Date.now(),
		});
		return stream;
	},
});

const model = runtime.getModel(provider, modelId);
assert.ok(model);
await runtime.streamSimple(model, { messages: [] }).result();
assert.equal(captured.timeoutMs, 7_200_000);
assert.equal(typeof captured.fetch, "function");
assert.notEqual(captured.fetch, globalThis.fetch);

const explicitFetch = async () => new Response();
await runtime
	.streamSimple(
		model,
		{ messages: [] },
		{ timeoutMs: 42, fetch: explicitFetch },
	)
	.result();
assert.equal(captured.timeoutMs, 42);
assert.equal(captured.fetch, explicitFetch);

const cwd = join(root, "project");
await mkdir(cwd, { recursive: true });
const { SettingsManager } = await importFromSource(
	"dist/core/settings-manager.js",
);
const { SessionManager } = await importFromSource(
	"dist/core/session-manager.js",
);
const { createAgentSession } = await importFromSource("dist/core/sdk.js");
const { session } = await createAgentSession({
	cwd,
	agentDir,
	model,
	modelRuntime: runtime,
	settingsManager: SettingsManager.inMemory({
		httpIdleTimeoutMs: 1_000,
		retry: { provider: { timeoutMs: 2_000 } },
	}),
	sessionManager: SessionManager.inMemory(cwd),
});
try {
	const stream = await session.agent.streamFunction(
		model,
		{ messages: [] },
		{},
	);
	await stream.result();
	assert.equal(captured.timeoutMs, 7_200_000);
	assert.equal(typeof captured.fetch, "function");
	assert.notEqual(captured.fetch, globalThis.fetch);
} finally {
	session.dispose();
}
