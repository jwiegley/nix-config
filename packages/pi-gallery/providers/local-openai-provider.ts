// Derived from gaurav-321/pi-local-llm at commit
// 57583beb3a1bd99c7ed31495f4a8e3b026242630 and modified for the Nix-managed
// Pi gallery. Licensed under Apache-2.0; the packaged derivatives include the
// upstream LICENSE file.

type ProviderModelConfig = Record<string, unknown>;
interface ExtensionAPI {
	registerProvider(id: string, config: Record<string, unknown>): void;
}

export interface LocalProviderConfig {
	id: string;
	name: string;
	baseUrl: string;
	apiKey: string;
}

interface ModelEntry {
	id?: unknown;
	name?: unknown;
	type?: unknown;
	architecture?: unknown;
	capabilities?: unknown;
	context_length?: unknown;
	max_context_length?: unknown;
	context_window?: unknown;
	max_model_len?: unknown;
	output_length?: unknown;
	max_tokens?: unknown;
	meta?: unknown;
	metadata?: unknown;
}

type ModelModality = "text" | "image" | "audio";
type InputModality = Exclude<ModelModality, "audio">;
interface ModelCapabilities {
	type: "chat" | "non-chat";
	inputModalities: InputModality[];
	reasoning: boolean;
}

interface CatalogModel {
	entry: ModelEntry & { id: string };
	capabilities: ModelCapabilities;
}

const DEFAULT_CONTEXT_WINDOW = 262_144;
const DEFAULT_MAX_TOKENS = 65_536;
const MAX_DISCOVERY_RESPONSE_BYTES = 1024 * 1024;
const MAX_DISCOVERY_MODEL_ENTRIES = 4096;
// Discovery runs once, at registration, so a timeout does not degrade to "slow"
// — it leaves the provider with no models until Pi restarts. The budget covers
// connect, response and JSON parse, and these hosts run jobs heavy enough to
// stall a loopback round trip well past half a second.
const FETCH_TIMEOUT_MS = 2_500;
const NON_CHAT_TYPES = new Set([
	"asr",
	"audio",
	"audio-sts",
	"audio-stt",
	"audio-tts",
	"audio_sts",
	"audio_stt",
	"audio_tts",
	"clip",
	"embedding",
	"image",
	"image-generation",
	"image_generation",
	"rerank",
	"reranker",
	"speech",
	"transcription",
	"tts",
	"whisper",
]);
const NON_CHAT_CAPABILITIES = new Set(["embedding", "reranker"]);
const NON_CHAT_ENDPOINT_CAPABILITIES = new Set([
	"audio_speech",
	"audio_transcriptions",
	"image_generation",
	"image_to_image",
]);
const runtimeProcess = (
	globalThis as unknown as { process: { emitWarning(message: string): void } }
).process;

function positiveInteger(...values: unknown[]): number | undefined {
	for (const value of values) {
		if (typeof value === "number" && Number.isSafeInteger(value) && value > 0)
			return value;
		if (typeof value === "string" && /^\d+$/.test(value)) {
			const parsed = Number(value);
			if (Number.isSafeInteger(parsed) && parsed > 0) return parsed;
		}
	}
	return undefined;
}

function nestedRecord(
	value: unknown,
	key: string,
): Record<string, unknown> | undefined {
	if (!value || typeof value !== "object" || Array.isArray(value))
		return undefined;
	const nested = (value as Record<string, unknown>)[key];
	return nested && typeof nested === "object" && !Array.isArray(nested)
		? (nested as Record<string, unknown>)
		: undefined;
}

function stringList(value: unknown): string[] | undefined {
	if (!Array.isArray(value)) return undefined;
	return value
		.filter((item): item is string => typeof item === "string")
		.map((item) => item.trim().toLowerCase());
}

function modalities(value: unknown): ModelModality[] | undefined {
	const normalized = stringList(value)?.filter(
		(item): item is ModelModality =>
			item === "text" || item === "image" || item === "audio",
	);
	return normalized && normalized.length > 0 ? normalized : undefined;
}

function capabilityNames(value: unknown): Set<string> {
	if (Array.isArray(value)) return new Set(stringList(value) ?? []);
	if (!value || typeof value !== "object") return new Set();
	return new Set(
		Object.entries(value as Record<string, unknown>).flatMap(
			([name, enabled]) => (enabled === true ? [name.toLowerCase()] : []),
		),
	);
}

function contextWindow(model: ModelEntry): number {
	const llamaSwap = nestedRecord(model.meta, "llamaswap");
	const metadata =
		model.metadata && typeof model.metadata === "object"
			? (model.metadata as Record<string, unknown>)
			: undefined;
	return (
		positiveInteger(
			model.max_model_len,
			model.context_length,
			model.max_context_length,
			model.context_window,
			llamaSwap?.context_length,
			llamaSwap?.context,
			llamaSwap?.max_context,
			llamaSwap?.max_context_length,
			metadata?.context_length,
			metadata?.context,
		) ?? DEFAULT_CONTEXT_WINDOW
	);
}

function outputLimit(model: ModelEntry, context: number): number {
	const llamaSwap = nestedRecord(model.meta, "llamaswap");
	return Math.min(
		positiveInteger(
			model.output_length,
			model.max_tokens,
			llamaSwap?.output_length,
			llamaSwap?.max_tokens,
		) ?? DEFAULT_MAX_TOKENS,
		context,
	);
}

function normalizeModel(model: unknown): CatalogModel | undefined {
	if (!model || typeof model !== "object" || Array.isArray(model)) return;
	const entry = model as ModelEntry;
	if (typeof entry.id !== "string" || entry.id.length === 0) return;

	const architecture =
		entry.architecture &&
		typeof entry.architecture === "object" &&
		!Array.isArray(entry.architecture)
			? (entry.architecture as Record<string, unknown>)
			: undefined;
	const input = modalities(architecture?.input_modalities);
	const output = modalities(architecture?.output_modalities);
	const names = capabilityNames(entry.capabilities);
	const type =
		typeof entry.type === "string"
			? entry.type.trim().toLowerCase()
			: undefined;
	const explicitChatModalities =
		input?.includes("text") === true && output?.includes("text") === true;
	const nonChat =
		(type !== undefined && NON_CHAT_TYPES.has(type)) ||
		(input !== undefined && !input.includes("text")) ||
		(output !== undefined && !output.includes("text")) ||
		[...names].some((name) => NON_CHAT_CAPABILITIES.has(name)) ||
		(!explicitChatModalities &&
			[...names].some((name) => NON_CHAT_ENDPOINT_CAPABILITIES.has(name)));
	const image =
		input === undefined ? names.has("vision") : input.includes("image");

	return {
		entry: entry as ModelEntry & { id: string },
		capabilities: {
			type: nonChat ? "non-chat" : "chat",
			inputModalities: image ? ["text", "image"] : ["text"],
			reasoning: names.has("reasoning") || names.has("thinking"),
		},
	};
}

function toPiModel(model: CatalogModel): ProviderModelConfig {
	const context = contextWindow(model.entry);
	return {
		id: model.entry.id,
		name:
			typeof model.entry.name === "string" && model.entry.name.length > 0
				? model.entry.name
				: model.entry.id,
		compat: {
			supportsStore: false,
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			maxTokensField: "max_tokens",
			supportsStrictMode: false,
		},
		reasoning: model.capabilities.reasoning,
		input: model.capabilities.inputModalities,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: context,
		maxTokens: outputLimit(model.entry, context),
	};
}

async function abortDiscovery(
	controller: AbortController,
	body: { cancel(): Promise<void> } | null,
): Promise<void> {
	controller.abort();
	try {
		await body?.cancel();
	} catch {
		// Aborting fetch may already have errored the body.
	}
}

async function readDiscoveryPayload(
	response: Response,
	controller: AbortController,
): Promise<unknown> {
	const contentLength = response.headers.get("content-length");
	if (
		contentLength !== null &&
		/^\d+$/.test(contentLength) &&
		Number(contentLength) > MAX_DISCOVERY_RESPONSE_BYTES
	) {
		await abortDiscovery(controller, response.body);
		throw new Error(`response exceeds ${MAX_DISCOVERY_RESPONSE_BYTES} bytes`);
	}

	const reader = response.body?.getReader();
	if (!reader) throw new Error("response has no body");
	const bytes = new Uint8Array(MAX_DISCOVERY_RESPONSE_BYTES);
	let length = 0;
	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			if (value.byteLength > MAX_DISCOVERY_RESPONSE_BYTES - length) {
				await abortDiscovery(controller, reader);
				throw new Error(
					`response exceeds ${MAX_DISCOVERY_RESPONSE_BYTES} bytes`,
				);
			}
			bytes.set(value, length);
			length += value.byteLength;
		}
	} finally {
		reader.releaseLock();
	}
	return JSON.parse(new TextDecoder().decode(bytes.subarray(0, length)));
}

async function discoverModels(
	config: LocalProviderConfig,
): Promise<ProviderModelConfig[]> {
	const url = `${config.baseUrl.replace(/\/$/, "")}/models`;
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
	try {
		const response = await fetch(url, {
			headers: {
				Accept: "application/json",
				Authorization: `Bearer ${config.apiKey}`,
			},
			signal: controller.signal,
		});
		if (!response.ok) {
			await abortDiscovery(controller, response.body);
			throw new Error(`${response.status} ${response.statusText}`);
		}
		const payload = await readDiscoveryPayload(response, controller);
		if (!payload || typeof payload !== "object" || Array.isArray(payload))
			throw new Error("response is not an object");
		const catalog = payload as {
			data?: unknown;
			models?: unknown;
		};
		let entries: unknown[];
		if (Array.isArray(catalog.data)) {
			entries = catalog.data;
		} else if (Array.isArray(catalog.models)) {
			entries = catalog.models;
		} else {
			throw new Error("response has no data/models array");
		}
		if (entries.length > MAX_DISCOVERY_MODEL_ENTRIES)
			throw new Error(
				`response has ${entries.length} model entries; limit is ${MAX_DISCOVERY_MODEL_ENTRIES}`,
			);
		return entries.flatMap((entry) => {
			const model = normalizeModel(entry);
			return model?.capabilities.type === "chat" ? [toPiModel(model)] : [];
		});
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		runtimeProcess.emitWarning(
			`[${config.id}] Cannot discover models from ${url}: ${detail}`,
		);
		return [];
	} finally {
		clearTimeout(timeout);
	}
}

export async function registerLocalProvider(
	pi: ExtensionAPI,
	config: LocalProviderConfig,
): Promise<void> {
	pi.registerProvider(config.id, {
		name: config.name,
		baseUrl: config.baseUrl,
		api: "openai-completions",
		apiKey: config.apiKey,
		authHeader: true,
		models: await discoverModels(config),
	});
}
