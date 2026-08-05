import { describe, expect, test } from "bun:test";

const helperPath = process.env.PI_BLACKHOLE_THRESHOLD_HELPER;
if (!helperPath) throw new Error("PI_BLACKHOLE_THRESHOLD_HELPER is required");

const { COMPACTION_CONTEXT_RATIO, resolveCompactionPressure } = await import(helperPath);

describe("Pi Blackhole compaction pressure", () => {
	test("uses 70 percent of the active Sol context", () => {
		expect(COMPACTION_CONTEXT_RATIO).toBe(0.7);
		expect(
			resolveCompactionPressure({ contextWindow: 1_050_000, tokens: 734_999 }, 81_000, 81_000),
		).toEqual({ source: "context", threshold: 735_000, tokens: 734_999 });
		expect(
			resolveCompactionPressure({ contextWindow: 1_050_000, tokens: 735_000 }, 81_000, 81_000),
		).toEqual({ source: "context", threshold: 735_000, tokens: 735_000 });
	});

	test("tracks the active context window when the model changes", () => {
		expect(
			resolveCompactionPressure({ contextWindow: 262_144, tokens: 183_500 }, 81_000, 81_000),
		).toEqual({ source: "context", threshold: 183_500, tokens: 183_500 });
	});

	test("retains Blackhole's configured token threshold as a compatibility fallback", () => {
		expect(resolveCompactionPressure({ contextWindow: 1_050_000, tokens: null }, 80_999, 81_000)).toEqual({
			source: "fallback",
			threshold: 81_000,
			tokens: 80_999,
		});
	});
});
