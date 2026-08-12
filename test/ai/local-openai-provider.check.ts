import llamaSwap from "../../packages/pi-gallery/providers/pi-provider-llama-swap.js";
import omlx from "../../packages/pi-gallery/providers/pi-provider-omlx.js";

function expectEqual(actual: unknown, expected: unknown, label: string): void {
	if (JSON.stringify(actual) !== JSON.stringify(expected)) {
		throw new Error(
			`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
		);
	}
}

function expect(condition: boolean, label: string): void {
	if (!condition) throw new Error(label);
}

type ProviderConfig = Record<string, unknown>;
type ProviderModel = Record<string, unknown>;
type WarningProcess = { emitWarning(warning: string | Error): void };
const warningProcess = (globalThis as unknown as { process: WarningProcess })
	.process;
const MAX_DISCOVERY_RESPONSE_BYTES = 1024 * 1024;
const MAX_DISCOVERY_MODEL_ENTRIES = 4096;
const QWEN_MODEL_ID = "Qwen3.6-27B-oQ6e-mtp";
const QWEN_THINKING_LEVEL_MAP = {
	minimal: null,
	low: null,
	medium: null,
	high: "high",
	xhigh: null,
	max: null,
};

function modelsFor(
	providers: Map<string, ProviderConfig>,
	id: string,
): ProviderModel[] {
	return registeredModels(providers.get(id), id);
}

function registeredModels(
	provider: ProviderConfig | undefined,
	label: string,
): ProviderModel[] {
	const models = provider?.models;
	if (!Array.isArray(models))
		throw new Error(`${label} did not register a model array`);
	return models as ProviderModel[];
}

const realFetch = globalThis.fetch;
const realEmitWarning = warningProcess.emitWarning;

try {
	const requests: Array<{ url: string; authorization: string | null }> = [];
	globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		const headers = new Headers(init?.headers);
		requests.push({ url, authorization: headers.get("authorization") });
		if (url.includes(":8080/")) {
			return Promise.resolve(
				Response.json({
					data: [
						{
							id: "GLM-5.2",
							type: "chat",
							architecture: {
								input_modalities: ["text"],
								output_modalities: ["text"],
							},
							capabilities: ["thinking"],
							meta: { llamaswap: { context_length: "9007199254740992" } },
						},
						{
							id: "bge-m3",
							type: "chat",
							architecture: {
								input_modalities: ["text"],
								output_modalities: ["text"],
							},
						},
						{
							id: "vision-reasoning-model",
							capabilities: { vision: false, reasoning: false },
						},
						{
							id: "plain-vision-capability",
							capabilities: { vision: true },
						},
						{
							id: "embedding-rerank-transcribe-chat",
							type: "chat",
							architecture: {
								input_modalities: ["text"],
								output_modalities: ["text"],
							},
						},
						{
							id: "unknown-metadata-model",
							type: "future-chat-kind",
							architecture: {
								input_modalities: ["future-input"],
								output_modalities: ["future-output"],
							},
							capabilities: ["future-capability"],
						},
						{
							id: "malformed-metadata-model",
							type: 42,
							architecture: {
								input_modalities: [42],
								output_modalities: [],
							},
							capabilities: { vision: 1, reasoning: "yes" },
						},
						{ id: "plain-embedding", type: "embedding" },
						{
							id: "plain-transcriber",
							architecture: {
								input_modalities: ["audio"],
								output_modalities: ["text"],
							},
						},
						{
							id: "plain-image-generator",
							architecture: {
								input_modalities: ["text"],
								output_modalities: ["image"],
							},
						},
						{
							id: "plain-reranker",
							capabilities: { reranker: true },
						},
						{
							id: "plain-speech-endpoint",
							capabilities: { audio_speech: true },
						},
					],
				}),
			);
		}
		return Promise.resolve(
			Response.json({
				data: [
					{ id: "DeepSeek-V4-Flash-0731-oQ8e-mtp", max_model_len: 262144 },
					{
						id: QWEN_MODEL_ID,
						max_model_len: 262144,
					},
					{
						id: "cohere-transcribe-03-2026-mlx-fp16",
						type: "transcription",
						max_model_len: 1024,
					},
				],
			}),
		);
	}) as typeof fetch;

	const providers = new Map<string, ProviderConfig>();
	const pi = {
		registerProvider: (id: string, config: ProviderConfig) =>
			providers.set(id, config),
	};
	await llamaSwap(pi);
	await omlx(pi);

	expectEqual(
		requests,
		[
			{
				url: "http://localhost:8080/v1/models",
				authorization: "Bearer dummy-key",
			},
			{
				url: "http://localhost:8000/v1/models",
				authorization: "Bearer dummy-key",
			},
		],
		"provider requests",
	);
	expectEqual([...providers.keys()], ["llama-swap", "omlx"], "provider IDs");
	const llamaModels = modelsFor(providers, "llama-swap");
	const omlxModels = modelsFor(providers, "omlx");
	expectEqual(
		llamaModels.map((model) => model.id),
		[
			"GLM-5.2",
			"bge-m3",
			"vision-reasoning-model",
			"plain-vision-capability",
			"embedding-rerank-transcribe-chat",
			"unknown-metadata-model",
			"malformed-metadata-model",
		],
		"llama-swap filtering",
	);
	expectEqual(
		llamaModels[0],
		{
			id: "GLM-5.2",
			name: "GLM-5.2",
			compat: {
				supportsStore: false,
				supportsDeveloperRole: false,
				supportsReasoningEffort: false,
				maxTokensField: "max_tokens",
				supportsStrictMode: false,
			},
			reasoning: true,
			input: ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			contextWindow: 262144,
			maxTokens: 65536,
		},
		"llama-swap metadata",
	);
	expectEqual(
		llamaModels.slice(1).map((model) => ({
			id: model.id,
			reasoning: model.reasoning,
			input: model.input,
		})),
		[
			{ id: "bge-m3", reasoning: false, input: ["text"] },
			{
				id: "vision-reasoning-model",
				reasoning: false,
				input: ["text"],
			},
			{
				id: "plain-vision-capability",
				reasoning: false,
				input: ["text", "image"],
			},
			{
				id: "embedding-rerank-transcribe-chat",
				reasoning: false,
				input: ["text"],
			},
			{
				id: "unknown-metadata-model",
				reasoning: false,
				input: ["text"],
			},
			{
				id: "malformed-metadata-model",
				reasoning: false,
				input: ["text"],
			},
		],
		"misleading llama-swap names",
	);
	expectEqual(
		omlxModels.map((model) => model.id),
		["DeepSeek-V4-Flash-0731-oQ8e-mtp", "Qwen3.6-27B-oQ6e-mtp"],
		"oMLX filtering",
	);
	expectEqual(
		{
			contextWindow: omlxModels[0].contextWindow,
			reasoning: omlxModels[0].reasoning,
			input: omlxModels[0].input,
		},
		{ contextWindow: 262144, reasoning: false, input: ["text"] },
		"oMLX conservative metadata defaults",
	);
	expectEqual(
		{ reasoning: omlxModels[1].reasoning, input: omlxModels[1].input },
		{ reasoning: false, input: ["text"] },
		"oMLX sparse capability metadata",
	);

	const codingAgentRoot = process.env.PI_CODING_AGENT_ROOT;
	if (!codingAgentRoot) throw new Error("PI_CODING_AGENT_ROOT is required");
	const piAiRoot = `${codingAgentRoot}/node_modules/@earendil-works/pi-ai/dist`;
	const { streamSimple } = await import(`${piAiRoot}/compat.js`);
	const { getSupportedThinkingLevels } = await import(`${piAiRoot}/models.js`);
	const { KEYBINDINGS } = await import(
		`${codingAgentRoot}/dist/core/keybindings.js`
	);
	const qwenModel = {
		...omlxModels[1],
		api: "openai-completions",
		provider: "omlx",
		baseUrl: "http://localhost:8000/v1",
		defaultThinkingLevel: "off",
		reasoning: true,
		input: ["text"],
		thinkingLevelMap: QWEN_THINKING_LEVEL_MAP,
		compat: {
			supportsReasoningEffort: false,
			thinkingFormat: "qwen-chat-template",
		},
	};
	expectEqual(
		getSupportedThinkingLevels(qwenModel),
		["off", "high"],
		"Qwen thinking levels",
	);
	expectEqual(
		KEYBINDINGS["app.thinking.cycle"].defaultKeys,
		"shift+tab",
		"Pi thinking-cycle binding",
	);
	const shapedPayloads: unknown[] = [];
	for (const reasoning of [undefined, "high"] as const) {
		const result = await streamSimple(
			qwenModel,
			{
				messages: [{ role: "user", content: "probe", timestamp: 1 }],
			},
			{
				apiKey: "test",
				reasoning,
				onPayload: (payload: unknown) => {
					shapedPayloads.push(payload);
					throw new Error("request captured before transport");
				},
			},
		).result();
		expect(
			result.stopReason === "error",
			"request capture did not stop transport",
		);
	}
	expectEqual(
		shapedPayloads.map((payload) => {
			const shaped = payload as Record<string, unknown>;
			return {
				chatTemplateKwargs: shaped.chat_template_kwargs,
				hasEnableThinking: Object.hasOwn(shaped, "enable_thinking"),
				hasReasoningEffort: Object.hasOwn(shaped, "reasoning_effort"),
			};
		}),
		[
			{
				chatTemplateKwargs: {
					enable_thinking: false,
					preserve_thinking: true,
				},
				hasEnableThinking: false,
				hasReasoningEffort: false,
			},
			{
				chatTemplateKwargs: {
					enable_thinking: true,
					preserve_thinking: true,
				},
				hasEnableThinking: false,
				hasReasoningEffort: false,
			},
		],
		"Qwen request shaping",
	);

	let failedBodyCancelled = false;
	let failedSignal: AbortSignal | null = null;
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
		failedSignal = init?.signal ?? null;
		return Promise.resolve(
			new Response(
				new ReadableStream<Uint8Array>({
					start(stream) {
						stream.enqueue(new TextEncoder().encode("down"));
					},
					cancel() {
						failedBodyCancelled = true;
					},
				}),
				{ status: 503, statusText: "Unavailable" },
			),
		);
	}) as typeof fetch;
	const warnings: string[] = [];
	warningProcess.emitWarning = (warning: string | Error) => {
		warnings.push(typeof warning === "string" ? warning : warning.message);
	};
	let failedProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			failedProvider = config;
		},
	});
	expectEqual(failedProvider?.models, [], "failed provider catalog");
	expectEqual(
		warnings,
		[
			"[omlx] Cannot discover models from http://localhost:8000/v1/models: 503 Unavailable",
		],
		"failure warning",
	);
	expect(failedBodyCancelled, "failed response body was not cancelled");
	expect(failedSignal?.aborted === true, "failed fetch was not aborted");

	const boundaryPrefix = '{"data":[{"id":"boundary-model"}],"padding":"';
	const boundarySuffix = '"}';
	const boundaryBody = `${boundaryPrefix}${"x".repeat(
		MAX_DISCOVERY_RESPONSE_BYTES -
			boundaryPrefix.length -
			boundarySuffix.length,
	)}${boundarySuffix}`;
	expectEqual(
		new TextEncoder().encode(boundaryBody).byteLength,
		MAX_DISCOVERY_RESPONSE_BYTES,
		"response byte boundary fixture",
	);
	globalThis.fetch = (() =>
		Promise.resolve(
			new Response(boundaryBody, {
				headers: {
					"content-length": String(MAX_DISCOVERY_RESPONSE_BYTES),
				},
			}),
		)) as typeof fetch;
	warnings.length = 0;
	let boundaryProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			boundaryProvider = config;
		},
	});
	expectEqual(
		registeredModels(boundaryProvider, "response byte boundary").map(
			(model) => model.id,
		),
		["boundary-model"],
		"response byte boundary catalog",
	);
	expectEqual(warnings, [], "response byte boundary warnings");

	let declaredBodyCancelled = false;
	let declaredReaderRequested = false;
	let declaredSignal: AbortSignal | null = null;
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
		declaredSignal = init?.signal ?? null;
		return Promise.resolve({
			ok: true,
			headers: new Headers({
				"content-length": String(MAX_DISCOVERY_RESPONSE_BYTES + 1),
			}),
			body: {
				cancel: () => {
					declaredBodyCancelled = true;
					return Promise.resolve();
				},
				getReader: () => {
					declaredReaderRequested = true;
					throw new Error("oversized declared body was read");
				},
			},
		} as unknown as Response);
	}) as typeof fetch;
	warnings.length = 0;
	let declaredProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			declaredProvider = config;
		},
	});
	expectEqual(declaredProvider?.models, [], "declared oversized catalog");
	expectEqual(
		warnings,
		[
			"[omlx] Cannot discover models from http://localhost:8000/v1/models: response exceeds 1048576 bytes",
		],
		"declared oversized warning",
	);
	expect(
		!declaredReaderRequested,
		"declared oversized body reader was requested",
	);
	expect(declaredBodyCancelled, "declared oversized body was not cancelled");
	expect(
		declaredSignal?.aborted === true,
		"declared oversized fetch was not aborted",
	);

	const boundaryBytes = new TextEncoder().encode(boundaryBody);
	let streamedBodyCancelled = false;
	let streamedSignal: AbortSignal | null = null;
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
		streamedSignal = init?.signal ?? null;
		return Promise.resolve(
			new Response(
				new ReadableStream<Uint8Array>({
					start(stream) {
						const middle = Math.floor(boundaryBytes.byteLength / 2);
						stream.enqueue(boundaryBytes.subarray(0, middle));
						stream.enqueue(boundaryBytes.subarray(middle));
						stream.enqueue(Uint8Array.of(0x20));
					},
					cancel() {
						streamedBodyCancelled = true;
					},
				}),
				{ headers: { "content-length": "128" } },
			),
		);
	}) as typeof fetch;
	warnings.length = 0;
	let streamedProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			streamedProvider = config;
		},
	});
	expectEqual(streamedProvider?.models, [], "streamed oversized catalog");
	expectEqual(
		warnings,
		[
			"[omlx] Cannot discover models from http://localhost:8000/v1/models: response exceeds 1048576 bytes",
		],
		"streamed oversized warning",
	);
	expect(streamedBodyCancelled, "streamed oversized body was not cancelled");
	expect(
		streamedSignal?.aborted === true,
		"streamed oversized fetch was not aborted",
	);

	const boundaryEntries = Array.from(
		{ length: MAX_DISCOVERY_MODEL_ENTRIES },
		(_value, index) => ({ id: `model-${index}` }),
	);
	globalThis.fetch = (() =>
		Promise.resolve(Response.json({ data: boundaryEntries }))) as typeof fetch;
	warnings.length = 0;
	let entryBoundaryProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			entryBoundaryProvider = config;
		},
	});
	expectEqual(
		registeredModels(entryBoundaryProvider, "model entry boundary").length,
		MAX_DISCOVERY_MODEL_ENTRIES,
		"model entry boundary catalog",
	);
	expectEqual(warnings, [], "model entry boundary warnings");

	const oversizedEntries = [...boundaryEntries, { id: "one-too-many" }];
	const oversizedEntriesBody = JSON.stringify({ data: oversizedEntries });
	expect(
		new TextEncoder().encode(oversizedEntriesBody).byteLength <
			MAX_DISCOVERY_RESPONSE_BYTES,
		"oversized entry fixture exceeded the response byte limit",
	);
	globalThis.fetch = (() =>
		Promise.resolve(new Response(oversizedEntriesBody))) as typeof fetch;
	warnings.length = 0;
	let oversizedEntriesProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			oversizedEntriesProvider = config;
		},
	});
	expectEqual(oversizedEntriesProvider?.models, [], "oversized entry catalog");
	expectEqual(
		warnings,
		[
			"[omlx] Cannot discover models from http://localhost:8000/v1/models: response has 4097 model entries; limit is 4096",
		],
		"oversized entry warning",
	);

	globalThis.fetch = (() =>
		Promise.resolve(
			new Response('{"data":[', {
				headers: { "content-type": "application/json" },
			}),
		)) as typeof fetch;
	warnings.length = 0;
	let malformedProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			malformedProvider = config;
		},
	});
	expectEqual(malformedProvider?.models, [], "malformed response catalog");
	expect(
		warnings.length === 1 &&
			warnings[0].startsWith(
				"[omlx] Cannot discover models from http://localhost:8000/v1/models:",
			),
		"malformed response warning",
	);

	// A hung server must abort rather than block registration forever, so the
	// signal has to reach fetch. Asserting it is wired costs nothing; waiting for
	// it to fire would add the whole timeout budget to every build.
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
		if (!init?.signal) throw new Error("fetch called without an abort signal");
		return Promise.reject(
			new DOMException("The operation was aborted.", "AbortError"),
		);
	}) as typeof fetch;
	warnings.length = 0;
	let abortedProvider: ProviderConfig | undefined;
	await omlx({
		registerProvider: (_id: string, config: ProviderConfig) => {
			abortedProvider = config;
		},
	});
	expectEqual(abortedProvider?.models, [], "aborted provider catalog");
	expectEqual(
		warnings,
		[
			"[omlx] Cannot discover models from http://localhost:8000/v1/models: The operation was aborted.",
		],
		"abort warning",
	);
} finally {
	globalThis.fetch = realFetch;
	warningProcess.emitWarning = realEmitWarning;
}
