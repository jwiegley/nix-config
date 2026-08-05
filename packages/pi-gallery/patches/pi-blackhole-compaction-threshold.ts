export const COMPACTION_CONTEXT_RATIO = 0.7;

export type CompactionPressure = {
	source: "context" | "fallback";
	threshold: number;
	tokens: number;
};

type ContextUsage = {
	contextWindow?: unknown;
	tokens?: unknown;
};

function isFiniteNumber(value: unknown): value is number {
	return typeof value === "number" && Number.isFinite(value);
}

export function resolveCompactionPressure(
	usage: ContextUsage | null | undefined,
	estimatedTokens: number,
	fallbackThreshold: number,
): CompactionPressure {
	if (
		isFiniteNumber(usage?.tokens) &&
		usage.tokens >= 0 &&
		isFiniteNumber(usage.contextWindow) &&
		usage.contextWindow > 0
	) {
		return {
			source: "context",
			threshold: Math.max(1, Math.floor(usage.contextWindow * COMPACTION_CONTEXT_RATIO)),
			tokens: usage.tokens,
		};
	}

	return {
		source: "fallback",
		threshold: fallbackThreshold,
		tokens: estimatedTokens,
	};
}
