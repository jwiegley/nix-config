import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const sourceRoot = process.argv[2];
if (!sourceRoot) throw new Error("usage: node pi-model-catalog-refresh.test.mjs SOURCE_ROOT");

const interactiveMode = readFileSync(
  join(sourceRoot, "dist/modes/interactive/interactive-mode.js"),
  "utf8",
);
assert.doesNotMatch(
  interactiveMode,
  /void this\.session\.modelRuntime\s*\.refresh\(\)\s*\.then\(\(\) => this\.updateAvailableProviderCount\(\)\)/,
  "interactive startup must not refresh remote model catalogs",
);

const selectorUrl = pathToFileURL(
  join(sourceRoot, "dist/modes/interactive/components/model-selector.js"),
).href;
const themeUrl = pathToFileURL(join(sourceRoot, "dist/modes/interactive/theme/theme.js")).href;
const { initTheme } = await import(themeUrl);
const { ModelSelectorComponent } = await import(selectorUrl);
initTheme("dark");

let refreshSignal;
let renderCount = 0;
const modelRuntime = {
  getAvailableSnapshot: () => [],
  getModel: () => undefined,
  getError: () => undefined,
  refresh: ({ signal } = {}) => {
    refreshSignal = signal;
    return new Promise(() => {});
  },
};
const tui = { requestRender: () => renderCount++ };

const startedAt = performance.now();
const selector = new ModelSelectorComponent(
  tui,
  undefined,
  {},
  modelRuntime,
  [],
  () => {},
  () => {},
);
assert.ok(performance.now() - startedAt < 500, "model selector construction blocked on refresh");

const deadline = performance.now() + 4_000;
while (selector.errorMessage !== "Model refresh timed out; showing cached models.") {
  if (performance.now() >= deadline) throw new Error("model catalog refresh did not time out");
  await new Promise((resolve) => setTimeout(resolve, 25));
}

assert.ok(refreshSignal?.aborted, "timed-out refresh was not aborted");
assert.ok(renderCount >= 2, "timed-out refresh did not request a new render");
selector.close();
