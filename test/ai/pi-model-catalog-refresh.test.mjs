import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const sourceRoot = process.argv[2];
if (!sourceRoot)
	throw new Error("usage: node pi-model-catalog-refresh.test.mjs SOURCE_ROOT");

const interactiveMode = readFileSync(
	join(sourceRoot, "dist/modes/interactive/interactive-mode.js"),
	"utf8",
);
const runStartup = interactiveMode.match(
	/async run\(\) \{([\s\S]*?)\/\/ Start version check asynchronously/,
)?.[1];
assert.ok(runStartup, "could not locate interactive startup body");
assert.doesNotMatch(
	runStartup,
	/(?:modelRuntime\s*\.refresh|refreshModelCatalogs)/,
	"interactive startup must not refresh remote model catalogs",
);

const selectorUrl = pathToFileURL(
	join(sourceRoot, "dist/modes/interactive/components/model-selector.js"),
).href;
const themeUrl = pathToFileURL(
	join(sourceRoot, "dist/modes/interactive/theme/theme.js"),
).href;
const { initTheme } = await import(themeUrl);
const { ModelSelectorComponent } = await import(selectorUrl);
initTheme("dark");

const realSetTimeout = globalThis.setTimeout;
const scheduledDelays = [];
globalThis.setTimeout = (callback, delay = 0, ...args) => {
	scheduledDelays.push(Number(delay));
	return realSetTimeout(callback, Number(delay) / 100, ...args);
};

try {
	let healthySignal;
	let healthyRenderCount = 0;
	const cachedModel = {
		provider: "cached",
		id: "snapshot",
		name: "Snapshot",
		api: "openai-completions",
		baseUrl: "http://127.0.0.1.invalid/v1",
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 1024,
		maxTokens: 256,
	};
	const healthyRuntime = {
		getAvailableSnapshot: () => [cachedModel],
		getModel: () => cachedModel,
		getError: () => undefined,
		refresh: ({ signal } = {}) => {
			healthySignal = signal;
			return new Promise((resolve) =>
				realSetTimeout(
					() => resolve({ aborted: false, errors: new Map() }),
					35,
				),
			);
		},
	};
	const healthyStartedAt = performance.now();
	const healthySelector = new ModelSelectorComponent(
		{ requestRender: () => healthyRenderCount++ },
		undefined,
		{},
		healthyRuntime,
		[],
		() => {},
		() => {},
	);
	assert.ok(
		performance.now() - healthyStartedAt < 500,
		"model selector construction blocked on refresh",
	);
	assert.deepEqual(
		healthySelector.allModels.map(({ provider, id }) => ({ provider, id })),
		[{ provider: "cached", id: "snapshot" }],
		"model selector did not render the cached snapshot immediately",
	);
	assert.deepEqual(
		scheduledDelays.filter((delay) => delay >= 2_000),
		[15_000],
		"model selector did not retain the 15-second refresh deadline",
	);
	const healthyDeadline = performance.now() + 1_000;
	while (healthySelector.refreshStatusMessage !== "Model catalogs refreshed.") {
		if (healthySelector.errorMessage)
			throw new Error(healthySelector.errorMessage);
		if (performance.now() >= healthyDeadline)
			throw new Error("healthy cold model catalog refresh did not complete");
		await new Promise((resolve) => realSetTimeout(resolve, 10));
	}
	assert.equal(
		healthySignal?.aborted,
		false,
		"healthy cold refresh was aborted",
	);
	assert.ok(
		healthyRenderCount >= 2,
		"healthy refresh did not request a new render",
	);
	healthySelector.dispose();

	let hungSignal;
	let hungRenderCount = 0;
	const hungSelector = new ModelSelectorComponent(
		{ requestRender: () => hungRenderCount++ },
		undefined,
		{},
		{
			getAvailableSnapshot: () => [],
			getModel: () => undefined,
			getError: () => undefined,
			refresh: ({ signal } = {}) => {
				hungSignal = signal;
				return new Promise(() => {});
			},
		},
		[],
		() => {},
		() => {},
	);
	const hungDeadline = performance.now() + 1_000;
	while (
		hungSelector.errorMessage !==
		"Model refresh timed out; showing cached models."
	) {
		if (performance.now() >= hungDeadline)
			throw new Error("model catalog refresh did not time out");
		await new Promise((resolve) => realSetTimeout(resolve, 10));
	}
	assert.ok(hungSignal?.aborted, "timed-out refresh was not aborted");
	assert.ok(
		hungRenderCount >= 2,
		"timed-out refresh did not request a new render",
	);
	hungSelector.dispose();
} finally {
	globalThis.setTimeout = realSetTimeout;
}
