#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { performance } from "node:perf_hooks";

function parseArgs(argv) {
  const result = { delayMs: 500, pi: null, selfTestTimeout: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--pi") {
      result.pi = argv[++index];
    } else if (argument === "--delay-ms") {
      result.delayMs = Number(argv[++index]);
    } else if (argument === "--self-test-timeout") {
      result.selfTestTimeout = true;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (!result.selfTestTimeout && !result.pi) throw new Error("--pi is required");
  if (!Number.isInteger(result.delayMs) || result.delayMs < 100 || result.delayMs > 600_000) {
    throw new Error("--delay-ms must be an integer from 100 through 600000");
  }
  return result;
}

function sleep(milliseconds) {
  return new Promise(resolve => {
    const timer = setTimeout(resolve, milliseconds);
    timer.unref?.();
  });
}

function childExit(child) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve({ code: child.exitCode, signal: child.signalCode });
  }
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
}

async function waitForExit(child, timeoutMs, graceMs = 2000) {
  const expired = Symbol("expired");
  const exit = childExit(child);
  let result = await Promise.race([exit, sleep(timeoutMs).then(() => expired)]);
  if (result !== expired) return result;

  child.kill("SIGTERM");
  result = await Promise.race([exit, sleep(graceMs).then(() => expired)]);
  if (result === expired) {
    child.kill("SIGKILL");
    result = await Promise.race([exit, sleep(graceMs).then(() => expired)]);
  }
  if (result === expired) throw new Error("timed-out child did not terminate after SIGKILL");
  throw new Error(`child did not exit within ${timeoutMs}ms`);
}

async function runTimeoutSelfTest() {
  const child = spawn(
    process.execPath,
    ["-e", "process.on('SIGTERM', () => {}); console.log('ready'); setInterval(() => {}, 1000)"],
    { stdio: ["ignore", "pipe", "ignore"] },
  );
  await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.stdout.once("data", resolve);
  });
  const started = performance.now();
  try {
    await waitForExit(child, 50, 100);
    throw new Error("timeout self-test child exited without exercising escalation");
  } catch (error) {
    if (!String(error).includes("did not exit within")) throw error;
  }
  const elapsedMs = performance.now() - started;
  if (child.exitCode === null && child.signalCode === null) {
    throw new Error("timeout self-test left its child running");
  }
  if (elapsedMs > 1000) throw new Error(`timeout escalation took ${elapsedMs}ms`);
  process.stdout.write(`${JSON.stringify({ timeoutSelfTestMs: Math.round(elapsedMs) })}\n`);
}

const options = parseArgs(process.argv.slice(2));
if (options.selfTestTimeout) {
  await runTimeoutSelfTest();
} else {
const { delayMs, pi } = options;
const root = await mkdtemp(join(tmpdir(), "pi-litellm-first-token-"));
const home = join(root, "home");
const agent = join(root, "agent");
const project = join(root, "project");
let server;
let child;
const heartbeatTimers = new Set();
const sockets = new Set();

try {
  await Promise.all([mkdir(home), mkdir(agent), mkdir(project)]);
  let headersSeen = false;
  let heartbeats = 0;
  let serverError = null;

  server = createServer(async (request, response) => {
    let heartbeat;
    try {
      for await (const _chunk of request) {
        // Consume the request before writing the streamed response.
      }
      headersSeen =
        request.headers["x-litellm-timeout"] === "7200" &&
        request.headers["x-litellm-stream-timeout"] === "7200";
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.flushHeaders();
      const heartbeatMs = Math.min(1000, Math.max(25, Math.floor(delayMs / 4)));
      heartbeat = setInterval(() => {
        heartbeats += 1;
        response.write(": litellm-heartbeat\n\n");
      }, heartbeatMs);
      heartbeatTimers.add(heartbeat);
      await new Promise(resolve => setTimeout(resolve, delayMs));
      response.write(
        'data: {"id":"proof","object":"chat.completion.chunk","created":1,"model":"delayed","choices":[{"index":0,"delta":{"role":"assistant","content":"delayed-ok"},"finish_reason":null}]}\n\n',
      );
      response.write(
        'data: {"id":"proof","object":"chat.completion.chunk","created":1,"model":"delayed","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n',
      );
      response.end("data: [DONE]\n\n");
    } catch (error) {
      serverError = error;
      response.destroy(error);
    } finally {
      if (heartbeat) {
        clearInterval(heartbeat);
        heartbeatTimers.delete(heartbeat);
      }
    }
  });
  server.on("connection", socket => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("server has no TCP address");

  await writeFile(
    join(agent, "models.json"),
    JSON.stringify({
      providers: {
        litellm: {
          api: "openai-completions",
          apiKey: "synthetic",
          baseUrl: `http://127.0.0.1:${address.port}/v1`,
          headers: {
            "x-litellm-stream-timeout": "7200",
            "x-litellm-timeout": "7200",
          },
          models: [
            {
              id: "delayed",
              name: "Delayed first token",
              reasoning: false,
              input: ["text"],
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
              contextWindow: 128000,
              maxTokens: 16384,
            },
          ],
        },
      },
    }),
  );

  const started = performance.now();
  child = spawn(
    pi,
    [
      "--print",
      "--offline",
      "--no-session",
      "--no-context-files",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-approve",
      "--provider",
      "litellm",
      "--model",
      "delayed",
      "verify delayed first token",
    ],
    {
      cwd: project,
      env: {
        ...process.env,
        HOME: home,
        PI_CODING_AGENT_DIR: agent,
        PI_OFFLINE: "1",
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", chunk => {
    stdout += chunk;
  });
  child.stderr.on("data", chunk => {
    stderr += chunk;
  });

  const { code, signal } = await waitForExit(child, delayMs + 30_000);
  const elapsedMs = performance.now() - started;
  if (serverError) throw serverError;
  if (code !== 0 || signal) {
    throw new Error(`Pi failed (${code ?? signal}): ${stderr.trim()}`);
  }
  if (!headersSeen) throw new Error("Pi omitted the 7200-second LiteLLM timeout headers");
  if (heartbeats < 1) throw new Error("server emitted no heartbeat before the first token");
  if (elapsedMs < delayMs) throw new Error(`Pi exited before the ${delayMs}ms first-token delay`);
  if (!stdout.includes("delayed-ok")) throw new Error(`Pi output omitted delayed content: ${stdout}`);

  process.stdout.write(`${JSON.stringify({ delayMs, elapsedMs: Math.round(elapsedMs), heartbeats })}\n`);
} finally {
  for (const timer of heartbeatTimers) clearInterval(timer);
  if (child && child.exitCode === null && child.signalCode === null) {
    child.kill("SIGKILL");
    await Promise.race([childExit(child).catch(() => null), sleep(2000)]);
  }
  for (const socket of sockets) socket.destroy();
  if (server) {
    server.closeAllConnections?.();
    if (server.listening) {
      await Promise.race([new Promise(resolve => server.close(resolve)), sleep(2000)]);
    }
  }
  await rm(root, { recursive: true, force: true });
}
}
