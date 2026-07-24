import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const source = process.argv[2];
assert.ok(source, "patched Pi source path is required");
const importFromSource = (relative) => import(pathToFileURL(join(source, relative)));

const { applyToolRendererWrappers } = await importFromSource(
  "dist/core/extensions/tool-renderers.js",
);

const execute = async () => ({ content: [{ type: "text", text: "unchanged" }] });
const parameters = { type: "object" };
const inheritedCall = (...args) => ({ args, render: () => ["inherited-call"] });
const inheritedResult = (...args) => ({ args, render: () => ["inherited-result"] });
const definition = {
  name: "edit",
  label: "Edit",
  description: "test",
  parameters,
  execute,
};
const inherited = {
  ...definition,
  renderShell: "self",
  renderCall: inheritedCall,
  renderResult: inheritedResult,
};
const order = [];
const errors = [];
const extensions = [
  {
    path: "/first.ts",
    toolRenderers: [
      (tool, stock) => {
        order.push(`first:${tool.name}:${stock.renderShell}`);
        const previous = stock.renderCall;
        return {
          renderCall(...args) {
            order.push("first-call");
            return previous(...args);
          },
        };
      },
    ],
  },
  {
    path: "/throwing.ts",
    toolRenderers: [() => {
      throw new Error("renderer boom");
    }],
  },
  {
    path: "/second.ts",
    toolRenderers: [
      (_tool, stock) => {
        order.push("second");
        const previous = stock.renderCall;
        return {
          renderShell: "default",
          renderCall(...args) {
            order.push("second-call");
            return previous(...args);
          },
        };
      },
    ],
  },
];

const wrapped = applyToolRendererWrappers(extensions, definition, inherited, (error) => {
  errors.push(error);
});
assert.equal(wrapped.execute, execute, "execution identity changed");
assert.equal(wrapped.parameters, parameters, "schema identity changed");
assert.equal(wrapped.description, definition.description);
assert.equal(wrapped.renderShell, "default");
assert.equal(errors.length, 1);
assert.deepEqual(
  { extensionPath: errors[0].extensionPath, event: errors[0].event, error: errors[0].error },
  { extensionPath: "/throwing.ts", event: "tool_renderer", error: "renderer boom" },
);

const args = { path: "x" };
const theme = { marker: "theme" };
const lastComponent = { marker: "last" };
const state = { marker: "state" };
const context = {
  args,
  toolCallId: "call-1",
  invalidate() {},
  lastComponent,
  state,
  cwd: "/tmp/project",
  executionStarted: true,
  argsComplete: true,
  isPartial: true,
  expanded: true,
  showImages: true,
  isError: true,
};
const callComponent = wrapped.renderCall(args, theme, context);
assert.equal(callComponent.args[0], args);
assert.equal(callComponent.args[1], theme);
assert.equal(callComponent.args[2], context);
assert.equal(callComponent.args[2].lastComponent, lastComponent);
assert.equal(callComponent.args[2].state, state);
assert.deepEqual(order, ["first:edit:self", "second", "second-call", "first-call"]);

const result = { content: [{ type: "image", data: "AA==", mimeType: "image/png" }] };
const options = { expanded: true, isPartial: true };
const resultComponent = wrapped.renderResult(result, options, theme, context);
assert.equal(resultComponent.args[0], result);
assert.equal(resultComponent.args[1], options);
assert.equal(resultComponent.args[2], theme);
assert.equal(resultComponent.args[3], context);

const foreign = applyToolRendererWrappers(
  [
    {
      path: "/generic.ts",
      toolRenderers: [(_tool, stock) => ({
        ...stock,
        renderCall: () => ({ render: () => ["foreign-call"] }),
        renderResult: () => ({ render: () => ["foreign-result"] }),
      })],
    },
  ],
  { name: "mcp_foreign", label: "MCP Foreign", description: "foreign", parameters, execute },
  undefined,
  (error) => errors.push(error),
);
assert.equal(foreign.renderCall().render()[0], "foreign-call");
assert.equal(foreign.renderResult().render()[0], "foreign-result");
assert.equal(foreign.execute, execute);

const { createToolHtmlRenderer } = await importFromSource(
  "dist/core/export-html/tool-renderer.js",
);
const htmlRenderer = createToolHtmlRenderer({
  getToolDefinition: () => foreign,
  theme: {},
  cwd: "/tmp/project",
  width: 80,
});
assert.match(htmlRenderer.renderCall("html-call", foreign.name, {}), /foreign-call/);
const htmlResult = htmlRenderer.renderResult(
  "html-call",
  foreign.name,
  [{ type: "text", text: "source" }],
  {},
  false,
);
assert.equal(htmlResult.collapsed, undefined, "identical collapsed HTML should remain deduplicated");
assert.match(htmlResult.expanded, /foreign-result/);

const extensionDir = await mkdtemp(join(tmpdir(), "pi-renderer-wrapper-"));
const registeringExtension = join(extensionDir, "register.mjs");
await writeFile(
  registeringExtension,
  `export default function (pi) {
    if (pi.registerToolRenderer.length !== 1) throw new Error("wrong renderer ABI arity");
    pi.registerToolRenderer((_tool, stock) => stock);
  }\n`,
);
const emptyExtension = join(extensionDir, "empty.mjs");
await writeFile(emptyExtension, "export default function () {}\n");
const { loadExtensions } = await importFromSource("dist/core/extensions/loader.js");
const firstLoad = await loadExtensions([registeringExtension], extensionDir);
assert.deepEqual(firstLoad.errors, []);
assert.equal(firstLoad.extensions[0].toolRenderers.length, 1);
const secondLoad = await loadExtensions([emptyExtension], extensionDir);
assert.deepEqual(secondLoad.errors, []);
assert.equal(secondLoad.extensions[0].toolRenderers.length, 0, "renderer registration leaked across reload runtimes");
