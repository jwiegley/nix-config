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

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function waitFor(condition: () => boolean, label: string): Promise<void> {
	for (let attempt = 0; attempt < 1000; attempt += 1) {
		if (condition()) return;
		await Promise.resolve();
	}
	throw new Error(label);
}

type ProviderConfig = Record<string, unknown>;
type ProviderModel = Record<string, unknown>;
const warningProcess = process;
const MAX_DISCOVERY_RESPONSE_BYTES = 1024 * 1024;
const MAX_DISCOVERY_MODEL_ENTRIES = 4096;
const LLAMA_MODEL_ID = "llama-reasoning-test-model";
const OMLX_DEFAULTS_MODEL_ID = "omlx-defaults-test-model";
const QWEN_MODEL_ID = "qwen-test-model";
const QWEN_THINKING_LEVEL_MAP = {
	minimal: null,
	low: null,
	medium: null,
	high: "high",
	xhigh: null,
	max: null,
};
const DEEPSEEK_MAX_THINKING_LEVEL_MAP = {
	minimal: null,
	low: null,
	medium: null,
	high: null,
	xhigh: null,
	max: "max",
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
const realSetTimeout = globalThis.setTimeout;
const realEmitWarning = warningProcess.emitWarning;
const realOmlxApiKey = warningProcess.env.OMLX_API_KEY;
const realClioOmlxApiKey = warningProcess.env.OMLX_CLIO_API_KEY;
const realHeraOmlxApiKey = warningProcess.env.OMLX_HERA_API_KEY;

try {
	warningProcess.env.OMLX_API_KEY = "gallery-test-key";
	warningProcess.env.OMLX_CLIO_API_KEY = "clio-gallery-test-key";
	warningProcess.env.OMLX_HERA_API_KEY = "hera-gallery-test-key";
	const llamaSwapEndpoints = [
		{
			id: "llama-swap",
			name: "llama-swap",
			baseUrl: "http://localhost:8080/v1",
		},
	] as const;
	const omlxEndpoints = [
		{
			id: "omlx",
			name: "oMLX",
			baseUrl: "http://localhost:8000/v1",
			apiKey: { env: "OMLX_API_KEY" },
		},
	] as const;
	const requests: Array<{ url: string; authorization: string | null }> = [];
	const omittedProviders = new Map<string, ProviderConfig>();
	let omittedRequests = 0;
	globalThis.fetch = (() => {
		omittedRequests += 1;
		throw new Error("omitted endpoints attempted discovery");
	}) as typeof fetch;
	const omittedPi = {
		registerProvider: (id: string, config: ProviderConfig) =>
			omittedProviders.set(id, config),
	};
	await llamaSwap(omittedPi);
	await omlx(omittedPi);
	expectEqual([...omittedProviders.keys()], [], "omitted endpoint providers");
	expectEqual(omittedRequests, 0, "omitted endpoint requests");
	await llamaSwap(omittedPi, []);
	await omlx(omittedPi, []);
	expectEqual([...omittedProviders.keys()], [], "empty endpoint providers");
	expectEqual(omittedRequests, 0, "empty endpoint requests");

	globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		const headers = new Headers(init?.headers);
		requests.push({ url, authorization: headers.get("authorization") });
		if (url.includes(":8080/")) {
			return Promise.resolve(
				Response.json({
					data: [
						{
							id: LLAMA_MODEL_ID,
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
					{ id: OMLX_DEFAULTS_MODEL_ID, max_model_len: 262144 },
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
	await llamaSwap(pi, llamaSwapEndpoints);
	await omlx(pi, omlxEndpoints);

	expectEqual(
		requests,
		[
			{
				url: "http://localhost:8080/v1/models",
				authorization: "Bearer dummy-key",
			},
			{
				url: "http://localhost:8000/v1/models",
				authorization: "Bearer gallery-test-key",
			},
		],
		"provider requests",
	);
	const managedLlamaSwapEndpoints = [
		{
			id: "p7",
			name: "Cedar 17",
			baseUrl: "http://catalog.test:8080/custom/v1",
		},
	] as const;
	const managedOmlxEndpoints = [
		{
			id: "q9",
			name: "Quartz 29",
			baseUrl: "http://catalog.test:18000/custom/v1",
			apiKey: { env: "OMLX_CLIO_API_KEY" },
		},
		{
			id: "r4",
			name: "Violet 41",
			baseUrl: "http://catalog.test:28000/custom/v1",
			apiKey: { env: "OMLX_HERA_API_KEY" },
		},
	] as const;
	const managedProviders = new Map<string, ProviderConfig>();
	const managedPi = {
		registerProvider: (id: string, config: ProviderConfig) =>
			managedProviders.set(id, config),
	};
	await llamaSwap(managedPi, managedLlamaSwapEndpoints);
	await omlx(managedPi, managedOmlxEndpoints);
	expectEqual(
		requests.slice(2),
		[
			{
				url: `${managedLlamaSwapEndpoints[0].baseUrl}/models`,
				authorization: "Bearer dummy-key",
			},
			{
				url: `${managedOmlxEndpoints[0].baseUrl}/models`,
				authorization: "Bearer clio-gallery-test-key",
			},
			{
				url: `${managedOmlxEndpoints[1].baseUrl}/models`,
				authorization: "Bearer hera-gallery-test-key",
			},
		],
		"managed provider requests",
	);
	expectEqual(
		managedProviders.get("p7")?.baseUrl,
		managedLlamaSwapEndpoints[0].baseUrl,
		"managed llama-swap base URL",
	);
	expectEqual(
		managedProviders.get("q9")?.baseUrl,
		managedOmlxEndpoints[0].baseUrl,
		"managed Clio oMLX base URL",
	);
	expectEqual(
		managedProviders.get("r4")?.baseUrl,
		managedOmlxEndpoints[1].baseUrl,
		"managed Hera oMLX base URL",
	);
	expectEqual(
		managedOmlxEndpoints.map(({ id }) => ({
			id,
			name: managedProviders.get(id)?.name,
			apiKey: managedProviders.get(id)?.apiKey,
		})),
		[
			{
				id: "q9",
				name: "Quartz 29",
				apiKey: "clio-gallery-test-key",
			},
			{
				id: "r4",
				name: "Violet 41",
				apiKey: "hera-gallery-test-key",
			},
		],
		"typed oMLX names and credentials",
	);
	expectEqual(
		managedProviders.get("p7")?.name,
		"Cedar 17",
		"opaque adapter name",
	);
	expectEqual(
		[...managedProviders.keys()],
		["p7", "q9", "r4"],
		"managed provider IDs",
	);
	expectEqual([...providers.keys()], ["llama-swap", "omlx"], "provider IDs");
	const llamaModels = modelsFor(providers, "llama-swap");
	const omlxModels = modelsFor(providers, "omlx");
	expectEqual(
		llamaModels.map((model) => model.id),
		[
			LLAMA_MODEL_ID,
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
			id: LLAMA_MODEL_ID,
			name: LLAMA_MODEL_ID,
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
		[OMLX_DEFAULTS_MODEL_ID, QWEN_MODEL_ID],
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
	const { InMemoryCredentialStore } = await import(
		`${piAiRoot}/auth/credential-store.js`
	);
	const { ModelRuntime } = await import(
		`${codingAgentRoot}/dist/core/model-runtime.js`
	);
	let dynamicModelId = "runtime-initial";
	let dynamicRequests = 0;
	globalThis.fetch = (() => {
		dynamicRequests += 1;
		return Promise.resolve(Response.json({ data: [{ id: dynamicModelId }] }));
	}) as typeof fetch;
	const dynamicRuntime = await ModelRuntime.create({
		credentials: new InMemoryCredentialStore(),
		modelsPath: null,
		refreshOnCreate: false,
	});
	await omlx(dynamicRuntime, omlxEndpoints);
	await dynamicRuntime.refresh({ allowNetwork: false, providers: ["omlx"] });
	expectEqual(
		dynamicRuntime.getModels("omlx").map((model) => model.id),
		["runtime-initial"],
		"offline runtime catalog",
	);
	expectEqual(dynamicRequests, 1, "offline refresh requests");

	dynamicModelId = "runtime-refreshed";
	const refreshedResult = await dynamicRuntime.refresh({
		allowNetwork: true,
		providers: ["omlx"],
	});
	expectEqual([...refreshedResult.errors.keys()], [], "dynamic refresh errors");
	expectEqual(
		dynamicRuntime.getModels("omlx").map((model) => model.id),
		["runtime-refreshed"],
		"dynamic runtime catalog",
	);
	expectEqual(dynamicRequests, 2, "dynamic refresh requests");
	const privateLocatorSentinel = "private-locator-sentinel";
	globalThis.fetch = (() =>
		Promise.reject(
			new Error(
				`request to ${privateLocatorSentinel} exposed transport details`,
			),
		)) as typeof fetch;
	const sanitizedRefresh = await dynamicRuntime.refresh({
		allowNetwork: true,
		providers: ["omlx"],
	});
	expectEqual(
		[...sanitizedRefresh.errors.keys()],
		["omlx"],
		"failed refresh provider",
	);
	const sanitizedRefreshError = String(sanitizedRefresh.errors.get("omlx"));
	expect(
		sanitizedRefreshError.includes(
			"[omlx] Model discovery failed: request failed",
		),
		"refresh failure was not sanitized",
	);
	expect(
		!sanitizedRefreshError.includes(privateLocatorSentinel),
		"refresh failure exposed transport details",
	);
	expectEqual(
		dynamicRuntime.getModels("omlx").map((model) => model.id),
		["runtime-refreshed"],
		"failed refresh changed the cached catalog",
	);

	const pendingRefreshes: Array<{
		signal: AbortSignal;
		resolve(response: Response): void;
	}> = [];
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) =>
		new Promise<Response>((resolve) => {
			if (!init?.signal) throw new Error("dynamic refresh has no abort signal");
			pendingRefreshes.push({ signal: init.signal, resolve });
		})) as typeof fetch;
	const olderRefresh = dynamicRuntime.refresh({
		allowNetwork: true,
		providers: ["omlx"],
	});
	await waitFor(
		() => pendingRefreshes.length === 1,
		"older dynamic refresh did not start",
	);
	const newerRefresh = dynamicRuntime.refresh({
		allowNetwork: true,
		providers: ["omlx"],
	});
	await waitFor(
		() => pendingRefreshes.length === 2,
		"newer dynamic refresh did not start",
	);
	expect(
		pendingRefreshes[0].signal.aborted,
		"older refresh was not superseded",
	);
	pendingRefreshes[1].resolve(
		Response.json({ data: [{ id: "runtime-newer" }] }),
	);
	const newerResult = await newerRefresh;
	expectEqual([...newerResult.errors.keys()], [], "newer refresh errors");
	pendingRefreshes[0].resolve(
		Response.json({ data: [{ id: "runtime-older" }] }),
	);
	await olderRefresh;
	await dynamicRuntime.refresh({ allowNetwork: false, providers: ["omlx"] });
	expectEqual(
		dynamicRuntime.getModels("omlx").map((model) => model.id),
		["runtime-newer"],
		"superseded runtime catalog",
	);

	globalThis.fetch = (() =>
		Promise.reject(new Error("temporary discovery failure"))) as typeof fetch;
	const failedRefresh = await dynamicRuntime.refresh({
		allowNetwork: true,
		providers: ["omlx"],
	});
	expectEqual(
		[...failedRefresh.errors.keys()],
		["omlx"],
		"dynamic refresh failure attribution",
	);
	expectEqual(
		dynamicRuntime.getModels("omlx").map((model) => model.id),
		["runtime-newer"],
		"last-known-good runtime catalog",
	);

	const { streamSimple } = await import(`${piAiRoot}/compat.js`);
	const { getSupportedThinkingLevels } = await import(`${piAiRoot}/models.js`);
	const { KEYBINDINGS } = await import(
		`${codingAgentRoot}/dist/core/keybindings.js`
	);
	const withDeadline = async <T>(
		promise: Promise<T>,
		label: string,
		onTimeout: () => void,
	): Promise<T> => {
		let timer: ReturnType<typeof realSetTimeout> | undefined;
		const deadline = new Promise<never>((_resolve, reject) => {
			timer = realSetTimeout(() => {
				onTimeout();
				reject(new Error(label));
			}, 5_000);
		});
		try {
			return await Promise.race([promise, deadline]);
		} finally {
			if (timer !== undefined) clearTimeout(timer);
		}
	};
	const encoder = new TextEncoder();
	const encodeSseRecord = (record: unknown): Uint8Array =>
		encoder.encode(`data: ${JSON.stringify(record)}\n\n`);
	type CompletionFixture = {
		apiKey: string;
		baseUrl: string;
		model: Record<string, unknown>;
	};
	const completionFixtures: CompletionFixture[] = [];
	for (const endpoint of managedOmlxEndpoints) {
		const config = managedProviders.get(endpoint.id);
		if (!config) throw new Error("managed completion provider is missing");
		expect(
			config.api === "openai-completions",
			"managed completion provider uses the wrong API",
		);
		expect(
			config.authHeader === true,
			"managed completion provider does not require bearer authentication",
		);
		const apiKey = config.apiKey;
		const baseUrl = config.baseUrl;
		if (typeof apiKey !== "string")
			throw new Error("managed completion credential is missing");
		if (typeof baseUrl !== "string")
			throw new Error("managed completion destination is missing");
		const discoveredModel = registeredModels(config, endpoint.id)[0];
		if (!discoveredModel)
			throw new Error("managed completion model is missing");
		const model = {
			...discoveredModel,
			api: "openai-completions",
			provider: endpoint.id,
			baseUrl,
		};
		completionFixtures.push({ apiKey, baseUrl, model });
		let responseBody: ReadableStream<Uint8Array> | null = null;
		let terminalRecordPulled = false;
		let responseCancelled = false;
		const completionFetch = async (
			input: RequestInfo | URL,
			init?: RequestInit,
		): Promise<Response> => {
			const request = new Request(input, init);
			expect(
				request.url === `${baseUrl.replace(/\/+$/, "")}/chat/completions`,
				"managed completion request used the wrong destination",
			);
			expect(
				request.headers.get("authorization") === `Bearer ${apiKey}`,
				"managed completion request used the wrong bearer",
			);
			const payloadText = await request.text();
			const payload: unknown = JSON.parse(payloadText);
			if (!isRecord(payload))
				throw new Error("managed completion payload is not an object");
			expect(payload.stream === true, "managed completion was not streamed");
			const nonAuthorizationHeaders = [...request.headers.entries()]
				.filter(([name]) => name.toLowerCase() !== "authorization")
				.map(([, value]) => value)
				.join("\n");
			const nonAuthorizationMaterial = `${request.url}\n${nonAuthorizationHeaders}\n${payloadText}`;
			for (const other of managedOmlxEndpoints) {
				const otherKey = warningProcess.env[other.apiKey.env];
				if (otherKey) {
					expect(
						!nonAuthorizationMaterial.includes(otherKey),
						"managed completion leaked a credential outside authorization",
					);
				}
			}
			const records = [
				encodeSseRecord({
					id: "completion-success",
					object: "chat.completion.chunk",
					created: 1,
					model: discoveredModel.id,
					choices: [
						{
							index: 0,
							delta: { role: "assistant", content: "bounded " },
							finish_reason: null,
						},
					],
				}),
				encodeSseRecord({
					id: "completion-success",
					object: "chat.completion.chunk",
					created: 1,
					model: discoveredModel.id,
					choices: [
						{
							index: 0,
							delta: { content: "stream" },
							finish_reason: "stop",
						},
					],
				}),
				encoder.encode("data: [DONE]\n\n"),
			];
			const response = new Response(
				new ReadableStream<Uint8Array>(
					{
						pull(controller) {
							const record = records.shift();
							if (!record) {
								controller.close();
								return;
							}
							controller.enqueue(record);
							if (records.length === 0) {
								terminalRecordPulled = true;
								controller.close();
							}
						},
						cancel() {
							responseCancelled = true;
						},
					},
					{ highWaterMark: 0 },
				),
				{ headers: { "content-type": "text/event-stream" } },
			);
			responseBody = response.body;
			return response;
		};
		const completionAbort = new AbortController();
		try {
			const completion = await withDeadline(
				streamSimple(
					model,
					{
						messages: [{ role: "user", content: "probe", timestamp: 1 }],
					},
					{
						apiKey,
						fetch: completionFetch,
						signal: completionAbort.signal,
					},
				).result(),
				"managed completion did not finish",
				() => completionAbort.abort(),
			);
			const completionContent: unknown = completion.content;
			if (
				!Array.isArray(completionContent) ||
				!completionContent.every(isRecord)
			) {
				throw new Error("managed completion content is malformed");
			}
			const completionText = completionContent
				.filter((block) => block.type === "text")
				.map((block) => {
					if (typeof block.text !== "string")
						throw new Error("managed completion text is malformed");
					return block.text;
				})
				.join("");
			expect(completionText === "bounded stream", "managed SSE text differed");
			expect(
				completion.stopReason === "stop",
				"managed SSE did not stop cleanly",
			);
			expect(
				terminalRecordPulled || responseCancelled,
				"managed SSE terminal record was neither consumed nor cancelled",
			);
			expect(responseBody?.locked === false, "managed SSE body stayed locked");
		} finally {
			completionAbort.abort();
		}
	}

	const abortFixture = completionFixtures[0];
	if (!abortFixture) throw new Error("managed abort fixture is missing");
	const callerAbort = new AbortController();
	let abortBody: ReadableStream<Uint8Array> | null = null;
	let abortBodyController:
		| ReadableStreamDefaultController<Uint8Array>
		| undefined;
	let fetchSignal: AbortSignal | null = null;
	let transportCancelled = false;
	let bodyReadStartedResolve: (() => void) | undefined;
	const bodyReadStarted = new Promise<void>((resolve) => {
		bodyReadStartedResolve = resolve;
	});
	let abortChunkSent = false;
	const abortFetch = async (
		input: RequestInfo | URL,
		init?: RequestInit,
	): Promise<Response> => {
		const request = new Request(input, init);
		expect(
			request.url ===
				`${abortFixture.baseUrl.replace(/\/+$/, "")}/chat/completions`,
			"aborted completion request used the wrong destination",
		);
		expect(
			request.headers.get("authorization") === `Bearer ${abortFixture.apiKey}`,
			"aborted completion request used the wrong bearer",
		);
		fetchSignal = init?.signal ?? null;
		expect(fetchSignal !== null, "completion fetch did not receive a signal");
		const body = new ReadableStream<Uint8Array>(
			{
				pull(controller) {
					abortBodyController = controller;
					if (abortChunkSent) return;
					abortChunkSent = true;
					controller.enqueue(
						encodeSseRecord({
							id: "completion-abort",
							object: "chat.completion.chunk",
							created: 1,
							model: abortFixture.model.id,
							choices: [
								{
									index: 0,
									delta: { role: "assistant", content: "partial" },
									finish_reason: null,
								},
							],
						}),
					);
					bodyReadStartedResolve?.();
				},
				cancel() {
					transportCancelled = true;
				},
			},
			{ highWaterMark: 0 },
		);
		fetchSignal?.addEventListener(
			"abort",
			() => {
				transportCancelled = true;
				abortBodyController?.error(
					new DOMException("Request was aborted", "AbortError"),
				);
			},
			{ once: true },
		);
		const response = new Response(body, {
			headers: { "content-type": "text/event-stream" },
		});
		abortBody = response.body;
		return response;
	};
	const abortResultPromise = streamSimple(
		abortFixture.model,
		{ messages: [{ role: "user", content: "probe", timestamp: 1 }] },
		{
			apiKey: abortFixture.apiKey,
			fetch: abortFetch,
			signal: callerAbort.signal,
		},
	).result();
	try {
		await withDeadline(
			bodyReadStarted,
			"managed completion body was not read",
			() => callerAbort.abort(),
		);
		callerAbort.abort();
		const aborted = await withDeadline(
			abortResultPromise,
			"managed completion did not honor caller abort",
			() => callerAbort.abort(),
		);
		expect(
			aborted.stopReason === "aborted",
			"managed completion was not aborted",
		);
		expect(fetchSignal?.aborted === true, "fetch-owned signal was not aborted");
		expect(transportCancelled, "aborted completion transport stayed open");
		expect(
			abortBody?.locked === false,
			"aborted completion body stayed locked",
		);
	} finally {
		callerAbort.abort();
	}
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
	const deepseekMaxModel = {
		...omlxModels[0],
		api: "openai-completions",
		provider: "omlx",
		baseUrl: "http://localhost:8000/v1",
		reasoning: true,
		input: ["text"],
		thinkingLevelMap: DEEPSEEK_MAX_THINKING_LEVEL_MAP,
		compat: {
			...(omlxModels[0].compat as Record<string, unknown>),
			supportsReasoningEffort: true,
			requiresReasoningContentOnAssistantMessages: true,
			thinkingFormat: "deepseek",
		},
	};
	expectEqual(
		getSupportedThinkingLevels(deepseekMaxModel),
		["off", "max"],
		"DeepSeek Max thinking levels",
	);
	const deepseekPayloads: unknown[] = [];
	for (const reasoning of [undefined, "max"] as const) {
		const result = await streamSimple(
			deepseekMaxModel,
			{ messages: [{ role: "user", content: "probe", timestamp: 1 }] },
			{
				apiKey: "test",
				reasoning,
				onPayload: (payload: unknown) => {
					deepseekPayloads.push(payload);
					throw new Error("request captured before transport");
				},
			},
		).result();
		expect(
			result.stopReason === "error",
			"DeepSeek request capture did not stop transport",
		);
	}
	expectEqual(
		deepseekPayloads.map((payload) => {
			const shaped = payload as Record<string, unknown>;
			return {
				thinking: shaped.thinking,
				reasoningEffort: shaped.reasoning_effort,
				hasChatTemplateKwargs: Object.hasOwn(shaped, "chat_template_kwargs"),
			};
		}),
		[
			{
				thinking: { type: "disabled" },
				reasoningEffort: undefined,
				hasChatTemplateKwargs: false,
			},
			{
				thinking: { type: "enabled" },
				reasoningEffort: "max",
				hasChatTemplateKwargs: false,
			},
		],
		"DeepSeek Max request shaping",
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				failedProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(failedProvider?.models, [], "failed provider catalog");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: HTTP 503"],
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				boundaryProvider = config;
			},
		},
		omlxEndpoints,
	);
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				declaredProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(declaredProvider?.models, [], "declared oversized catalog");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: request failed"],
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				streamedProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(streamedProvider?.models, [], "streamed oversized catalog");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: request failed"],
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				entryBoundaryProvider = config;
			},
		},
		omlxEndpoints,
	);
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				oversizedEntriesProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(oversizedEntriesProvider?.models, [], "oversized entry catalog");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: request failed"],
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
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				malformedProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(malformedProvider?.models, [], "malformed response catalog");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: request failed"],
		"malformed response warning",
	);

	// Exercise the real timeout path without adding 2.5 seconds to every build.
	const discoveryDelays: number[] = [];
	globalThis.setTimeout = ((callback: () => void, delay?: number) => {
		discoveryDelays.push(Number(delay));
		return realSetTimeout(callback, 0);
	}) as typeof setTimeout;
	globalThis.fetch = ((_input: RequestInfo | URL, init?: RequestInit) => {
		const signal = init?.signal;
		if (!signal) throw new Error("fetch called without an abort signal");
		return new Promise<Response>((_resolve, reject) => {
			signal.addEventListener(
				"abort",
				() =>
					reject(new DOMException("The operation was aborted.", "AbortError")),
				{ once: true },
			);
		});
	}) as typeof fetch;
	warnings.length = 0;
	let abortedProvider: ProviderConfig | undefined;
	await omlx(
		{
			registerProvider: (_id: string, config: ProviderConfig) => {
				abortedProvider = config;
			},
		},
		omlxEndpoints,
	);
	expectEqual(abortedProvider?.models, [], "aborted provider catalog");
	expectEqual(discoveryDelays, [2_500], "local discovery timeout budget");
	expectEqual(
		warnings,
		["[omlx] Model discovery failed: request aborted"],
		"abort warning",
	);

	globalThis.setTimeout = realSetTimeout;
	const partialRequestStart = requests.length;
	globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
		const url = String(input);
		const headers = new Headers(init?.headers);
		requests.push({ url, authorization: headers.get("authorization") });
		return Promise.resolve(Response.json({ data: [] }));
	}) as typeof fetch;
	delete warningProcess.env.OMLX_CLIO_API_KEY;
	warnings.length = 0;
	const partialProviders = new Map<string, ProviderConfig>();
	await omlx(
		{
			registerProvider: (id: string, config: ProviderConfig) =>
				partialProviders.set(id, config),
		},
		managedOmlxEndpoints,
	);
	expectEqual(
		[...partialProviders.keys()],
		["r4"],
		"missing credential skips only its provider",
	);
	expectEqual(
		requests.slice(partialRequestStart),
		[
			{
				url: `${managedOmlxEndpoints[1].baseUrl}/models`,
				authorization: "Bearer hera-gallery-test-key",
			},
		],
		"missing credential makes no request for its provider",
	);
	expectEqual(
		warnings,
		["[q9] Credential environment is unset; provider was not registered"],
		"missing environment key warning",
	);
} finally {
	globalThis.fetch = realFetch;
	globalThis.setTimeout = realSetTimeout;
	warningProcess.emitWarning = realEmitWarning;
	if (realOmlxApiKey === undefined) delete warningProcess.env.OMLX_API_KEY;
	else warningProcess.env.OMLX_API_KEY = realOmlxApiKey;
	if (realClioOmlxApiKey === undefined)
		delete warningProcess.env.OMLX_CLIO_API_KEY;
	else warningProcess.env.OMLX_CLIO_API_KEY = realClioOmlxApiKey;
	if (realHeraOmlxApiKey === undefined)
		delete warningProcess.env.OMLX_HERA_API_KEY;
	else warningProcess.env.OMLX_HERA_API_KEY = realHeraOmlxApiKey;
}
