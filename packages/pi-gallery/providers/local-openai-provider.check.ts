import llamaSwap from "./pi-provider-llama-swap.js";
import omlx from "./pi-provider-omlx.js";

function expectEqual(actual: unknown, expected: unknown, label: string): void {
	if (JSON.stringify(actual) !== JSON.stringify(expected)) {
		throw new Error(
			`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
		);
	}
}

type ProviderConfig = Record<string, unknown>;
type ProviderModel = Record<string, unknown>;
type WarningProcess = { emitWarning(warning: string | Error): void };
const warningProcess = (globalThis as unknown as { process: WarningProcess })
	.process;

function modelsFor(
	providers: Map<string, ProviderConfig>,
	id: string,
): ProviderModel[] {
	const models = providers.get(id)?.models;
	if (!Array.isArray(models))
		throw new Error(`${id} did not register a model array`);
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
							meta: { llamaswap: { context_length: "9007199254740992" } },
						},
						{ id: "bge-m3" },
						{ id: "granite-speech-4.1-2b" },
					],
				}),
			);
		}
		return Promise.resolve(
			Response.json({
				data: [
					{ id: "DeepSeek-V4-Flash-0731-oQ8e-mtp", max_model_len: 262144 },
					{ id: "Qwen3.6-27B-oQ6e-mtp", max_model_len: 262144 },
					{ id: "cohere-transcribe-03-2026-mlx-fp16", max_model_len: 1024 },
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
				url: "http://127.0.0.1:8080/v1/models",
				authorization: "Bearer local-no-auth",
			},
			{
				url: "http://127.0.0.1:8000/v1/models",
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
		["GLM-5.2"],
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
		omlxModels.map((model) => model.id),
		["DeepSeek-V4-Flash-0731-oQ8e-mtp", "Qwen3.6-27B-oQ6e-mtp"],
		"oMLX filtering",
	);
	expectEqual(omlxModels[0].contextWindow, 262144, "oMLX server context");

	globalThis.fetch = (() =>
		Promise.resolve(
			new Response("down", { status: 503, statusText: "Unavailable" }),
		)) as typeof fetch;
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
			"[omlx] Cannot discover models from http://127.0.0.1:8000/v1/models: 503 Unavailable",
		],
		"failure warning",
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
			"[omlx] Cannot discover models from http://127.0.0.1:8000/v1/models: The operation was aborted.",
		],
		"abort warning",
	);
} finally {
	globalThis.fetch = realFetch;
	warningProcess.emitWarning = realEmitWarning;
}
