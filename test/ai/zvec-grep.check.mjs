import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, stat, writeFile } from "node:fs/promises";
import { createServer as createHttpServer } from "node:http";
import { createRequire } from "node:module";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

const pkg = process.argv[2];
const root = join(pkg, "lib/node_modules/@zvec/zvec-grep");
const load = (file) => import(pathToFileURL(join(root, "dist", file)));
const require = createRequire(join(root, "package.json"));
const { Client } = require("@modelcontextprotocol/client");
const { StdioClientTransport } = require("@modelcontextprotocol/client/stdio");
const { OpenAiCompatibleTextEmbeddingModel } = await load("engine/models/backends/qwen.js");
const { getEmbeddingModelCatalogEntry } = await load("engine/models/catalog.js");
const { DaemonInstanceLock, readInstanceRecord, serverStatus, stopServer } = await load("daemon/server-controller.js");

const expectedEntry = JSON.parse(process.argv[3]);
const entry = getEmbeddingModelCatalogEntry(expectedEntry.reference);
assert.deepEqual(entry, expectedEntry);
assert.equal(getEmbeddingModelCatalogEntry(process.argv[4]).requestTimeoutMs, undefined);
for (const [endpoint, expected] of [
  ["https://hera.lan:8443", "https://hera.lan:8443/v1/embeddings"],
  ["https://hera.lan:8443/", "https://hera.lan:8443/v1/embeddings"],
  ["https://hera.lan:8443/v1", "https://hera.lan:8443/v1/embeddings"],
  ["https://hera.lan:8443/v1/", "https://hera.lan:8443/v1/embeddings"],
  ["https://hera.lan:8443/v1/embeddings", "https://hera.lan:8443/v1/embeddings"],
  ["https://example.test/custom/embeddings?api-version=1", "https://example.test/custom/embeddings?api-version=1"],
]) {
  const model = new OpenAiCompatibleTextEmbeddingModel(entry, { endpoint, apiKey: "dummy-key" }, {
    fetch: async (url, options) => {
      assert.equal(url, expected);
      assert.equal(options.method, "POST");
      assert.equal(options.headers.Authorization, "Bearer dummy-key");
      assert.deepEqual(JSON.parse(options.body), {
        model: expectedEntry.model, input: ["endpoint probe"], dimensions: expectedEntry.dimension, encoding_format: "float",
      });
      return Response.json({ data: [{ index: 0, embedding: Array(expectedEntry.dimension).fill(0.5) }] });
    },
  });
  assert.equal((await model.embed([{ kind: "text", text: "endpoint probe" }])).vectors[0].length, expectedEntry.dimension);
  await model.dispose();
}

const home = await mkdtemp(join(tmpdir(), "zg-contract-"));
const state = join(home, "state");
const workspace = join(home, "repo");
const env = { HOME: home, PATH: process.env.PATH, ZVEC_GREP_HOME: state };
const clients = [];
try {
  const lock = await DaemonInstanceLock.acquire(state, "http://127.0.0.1:1/mcp", "search-rg");
  try {
    assert.equal((await readInstanceRecord(state)).mcpToolset, "search-rg");
    await lock.markReady();
    assert.equal((await readInstanceRecord(state)).ready, true);
    assert.equal((await serverStatus(state)).ready, false);
  } finally {
    await lock.release();
  }
  assert.equal(await readInstanceRecord(state), undefined);

  const listener = createServer();
  await new Promise((resolve, reject) => {
    listener.once("error", reject);
    listener.listen(0, "127.0.0.1", resolve);
  });
  const port = listener.address().port;
  await new Promise((resolve) => listener.close(resolve));
  await mkdir(workspace);
  await writeFile(join(workspace, "probe.txt"), "zg-runtime-needle\n");

  let daemonPid;
  for (let i = 0; i < 2; i++) {
    const client = new Client({ name: "zg-contract", version: "1" });
    clients.push(client);
    await client.connect(new StdioClientTransport({
      command: join(pkg, "bin/zg-mcp"),
      args: ["--home", state, "--listen", `127.0.0.1:${port}`],
      cwd: workspace,
      env,
    }));
    assert.deepEqual((await client.listTools()).tools.map((tool) => tool.name).sort(), ["zvec_grep_rg", "zvec_grep_search"]);
    const status = await serverStatus(state);
    assert.equal(status.ready, true);
    assert.equal((await readInstanceRecord(state)).ready, true);
    if (i === 0) daemonPid = status.pid;
    else assert.equal(status.pid, daemonPid);
    const result = await client.callTool({ name: "zvec_grep_rg", arguments: { root: workspace, command: "rg zg-runtime-needle probe.txt" } });
    assert.notEqual(result.isError, true);
    assert.match(JSON.stringify(result.content), /zg-runtime-needle/);
    await client.close();
  }
  assert.equal(await stat(join(workspace, ".zvec-grep")).then(() => true, (error) => {
    if (error.code !== "ENOENT") throw error;
    return false;
  }), false);

  const api = createHttpServer(async (request, response) => {
    assert.equal(request.url, "/v1/embeddings");
    let body = "";
    for await (const chunk of request) body += chunk;
    const input = JSON.parse(body);
    assert.equal(input.model, expectedEntry.model);
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({ data: input.input.map((_, index) => ({ index, embedding: Array(expectedEntry.dimension).fill(0.5) })) }));
  });
  try {
    await new Promise((resolve) => api.listen(0, "127.0.0.1", resolve));
    for (const cancel of [false, true]) {
      const controller = new AbortController();
      const model = new OpenAiCompatibleTextEmbeddingModel(
        { ...entry, requestTimeoutMs: cancel ? 600000 : 5 },
        { apiKey: "dummy-key" },
        { fetch: async (_, { signal }) => ({
          ok: true, status: 200,
          json: () => new Promise((resolve, reject) => {
            signal.addEventListener("abort", () => reject(signal.reason), { once: true });
            if (cancel) controller.abort();
          }),
        }) },
      );
      await assert.rejects(model.embed([{ kind: "text", text: "timeout probe" }], { signal: controller.signal }), { name: cancel ? "AbortError" : "TimeoutError" });
      await model.dispose();
    }
    const cli = (args) => promisify(execFile)(join(pkg, "bin/zg"), args, { cwd: workspace, env, timeout: 15000, killSignal: "SIGKILL" });
    await cli(["index", "--embedding", entry.reference, "--api-key", "dummy-key", "--endpoint", `http://127.0.0.1:${api.address().port}`, "--embedding-concurrency", "16", "--rebuild", "--allow-remote", "--mode", "direct"]);
    const result = await cli(["query", "zg-runtime-needle", "--allow-remote", "--mode", "direct"]);
    assert.match(result.stdout, /probe.txt/);
  } finally {
    await new Promise((resolve) => api.close(resolve));
  }
} finally {
  await Promise.all(clients.map((client) => client.close()));
  await stopServer(state, 5000);
  assert.equal(await readInstanceRecord(state), undefined);
  await rm(home, { recursive: true });
}
console.log("zg endpoint, daemon lifecycle, two-tool MCP, ripgrep, and native index/search checks passed");
