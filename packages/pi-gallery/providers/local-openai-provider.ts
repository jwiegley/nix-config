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
	architecture?: { input_modalities?: unknown };
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

const DEFAULT_CONTEXT_WINDOW = 262_144;
const DEFAULT_MAX_TOKENS = 65_536;
const FETCH_TIMEOUT_MS = 500;
const NON_CHAT_ID =
	/(?:^|[-_.:/])(asr|audio|bge|clip|embed(?:ding)?|rerank(?:er)?|speech|transcri(?:be|ption)|tts|whisper)(?:$|[-_.:/])/i;
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

function isChatModel(model: unknown): model is ModelEntry & { id: string } {
	if (!model || typeof model !== "object" || Array.isArray(model)) return false;
	const entry = model as ModelEntry;
	if (
		typeof entry.id !== "string" ||
		entry.id.length === 0 ||
		NON_CHAT_ID.test(entry.id)
	)
		return false;
	if (
		typeof entry.type === "string" &&
		/embedding|rerank|audio|speech|transcri/i.test(entry.type)
	)
		return false;
	const modalities = entry.architecture?.input_modalities;
	return !Array.isArray(modalities) || modalities.includes("text");
}

function imageCapable(model: ModelEntry): boolean {
	if (Array.isArray(model.architecture?.input_modalities)) {
		return model.architecture.input_modalities.includes("image");
	}
	if (
		model.capabilities &&
		typeof model.capabilities === "object" &&
		!Array.isArray(model.capabilities)
	) {
		return (model.capabilities as Record<string, unknown>).vision === true;
	}
	return /(?:^|[-_.:/])(vision|vl|multimodal)(?:$|[-_.:/])/i.test(
		String(model.id),
	);
}

function reasoningCapable(model: ModelEntry): boolean {
	if (Array.isArray(model.capabilities)) {
		return model.capabilities.some(
			(item) => typeof item === "string" && /reason|thinking/i.test(item),
		);
	}
	if (model.capabilities && typeof model.capabilities === "object") {
		const reasoning = (model.capabilities as Record<string, unknown>).reasoning;
		if (reasoning === true) return true;
	}
	return /(?:deepseek|glm|gpt-oss|magistral|qwen3|qwq|reasoning|thinking)/i.test(
		String(model.id),
	);
}

function toPiModel(model: ModelEntry & { id: string }): ProviderModelConfig {
	const context = contextWindow(model);
	return {
		id: model.id,
		name:
			typeof model.name === "string" && model.name.length > 0
				? model.name
				: model.id,
		compat: {
			supportsStore: false,
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			maxTokensField: "max_tokens",
			supportsStrictMode: false,
		},
		reasoning: reasoningCapable(model),
		input: imageCapable(model) ? ["text", "image"] : ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: context,
		maxTokens: outputLimit(model, context),
	};
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
		if (!response.ok)
			throw new Error(`${response.status} ${response.statusText}`);
		const payload = (await response.json()) as {
			data?: unknown;
			models?: unknown;
		};
		let entries: unknown[];
		if (Array.isArray(payload.data)) {
			entries = payload.data;
		} else if (Array.isArray(payload.models)) {
			entries = payload.models;
		} else {
			throw new Error("response has no data/models array");
		}
		return entries.flatMap((entry) =>
			isChatModel(entry) ? [toPiModel(entry)] : [],
		);
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
