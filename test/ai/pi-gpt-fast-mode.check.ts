import { expect, mock, test } from "bun:test";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_GPT_FAST_MODE_ROOT;
const runtimeRoot = process.env.PI_GPT_FAST_MODE_RUNTIME;
const configJson = process.env.PI_GPT_FAST_MODE_CONFIG_JSON;
if (!packageRoot || !runtimeRoot || !configJson) {
  throw new Error("PI_GPT_FAST_MODE_ROOT, PI_GPT_FAST_MODE_RUNTIME, and PI_GPT_FAST_MODE_CONFIG_JSON are required");
}

const expectedConfig = {
  persist: false,
  desired: false,
  tier: "priority",
  models: [
    "openai/gpt-5.4",
    "openai/gpt-5.5",
    "openai/gpt-5.6",
    "openai/gpt-5.6-luna",
    "openai/gpt-5.6-terra",
    "openai/gpt-5.6-sol",
    "openai-codex/gpt-5.4",
    "openai-codex/gpt-5.5",
    "openai-codex/gpt-5.6",
    "openai-codex/gpt-5.6-luna",
    "openai-codex/gpt-5.6-terra",
    "openai-codex/gpt-5.6-sol",
  ],
  indicator: "status",
};
expect(JSON.parse(configJson)).toEqual(expectedConfig);

const agentDir = join(runtimeRoot, "agent");
const projectDir = join(runtimeRoot, "project");
const configPath = join(agentDir, "extensions", "pi-gpt-fast-mode", "config.json");
await mkdir(dirname(configPath), { recursive: true });
await mkdir(projectDir, { recursive: true });
await writeFile(configPath, `${JSON.stringify(expectedConfig, null, 2)}\n`, "utf8");
const originalConfig = await readFile(configPath, "utf8");

mock.module("@earendil-works/pi-coding-agent", () => ({
  getAgentDir: () => agentDir,
}));

type Handler = (event: unknown, context: Context) => unknown;
type Command = {
  handler: (args: string, context: Context) => Promise<void>;
};
type Context = {
  cwd: string;
  hasUI: false;
  model: { provider: string; id: string };
  ui: { notify: () => void };
};

const { default: registerFastMode } = await import(
  pathToFileURL(join(packageRoot, "index.ts")).href
);

function context(provider: string, id: string): Context {
  return {
    cwd: projectDir,
    hasUI: false,
    model: { provider, id },
    ui: { notify() {} },
  };
}

function createHarness() {
  const handlers = new Map<string, Handler[]>();
  const commands = new Map<string, Command>();
  registerFastMode({
    getFlag: () => false,
    on(event: string, handler: Handler) {
      const current = handlers.get(event) ?? [];
      current.push(handler);
      handlers.set(event, current);
    },
    registerCommand(name: string, command: Command) {
      commands.set(name, command);
    },
    registerFlag() {},
  } as never);

  return {
    commands,
    handlers,
    async emit(event: string, value: unknown, ctx: Context): Promise<unknown> {
      let result: unknown;
      for (const handler of handlers.get(event) ?? []) {
        const next = await handler(value, ctx);
        if (next !== undefined) result = next;
      }
      return result;
    },
  };
}

test("managed GPT Fast Mode supports GPT-5.6 and real subagent handoff without network", async () => {
  const previousHandoff = process.env.PI_GPT_FAST_MODE;
  try {
    delete process.env.PI_GPT_FAST_MODE;

    const parent = createHarness();
    const parentContext = context("anthropic", "claude-sonnet-4");
    await parent.emit("session_start", {}, parentContext);
    expect(process.env.PI_GPT_FAST_MODE).toBe("0");
    expect(parent.commands.has("fast")).toBe(true);
    expect(parent.handlers.has("before_provider_request")).toBe(true);

    await parent.commands.get("fast")!.handler("on", parentContext);
    expect(process.env.PI_GPT_FAST_MODE).toBe("1");
    expect(
      await parent.emit("before_provider_request", { payload: {} }, parentContext),
    ).toBeUndefined();

    const child = createHarness();
    const openAi = context("openai", "gpt-5.6-luna");
    await child.emit("session_start", {}, openAi);
    expect(process.env.PI_GPT_FAST_MODE).toBe("1");

    const firstPayload = { model: "gpt-5.6-luna", messages: [] };
    expect(
      await child.emit("before_provider_request", { payload: firstPayload }, openAi),
    ).toEqual({
      ...firstPayload,
      service_tier: "priority",
    });
    expect(firstPayload).not.toHaveProperty("service_tier");

    const codex = context("openai-codex", "gpt-5.6-sol");
    await child.emit("model_select", { model: codex.model }, codex);
    expect(await child.emit("before_provider_request", { payload: {} }, codex)).toEqual({
      service_tier: "priority",
    });

    const unsupported = context("anthropic", "claude-sonnet-4");
    await child.emit("model_select", { model: unsupported.model }, unsupported);
    expect(
      await child.emit("before_provider_request", { payload: {} }, unsupported),
    ).toBeUndefined();

    await child.emit("model_select", { model: openAi.model }, openAi);
    expect(await child.emit("before_provider_request", { payload: {} }, openAi)).toEqual({
      service_tier: "priority",
    });
    expect(process.env.PI_GPT_FAST_MODE).toBe("1");
    expect(await readFile(configPath, "utf8")).toBe(originalConfig);
  } finally {
    if (previousHandoff === undefined) delete process.env.PI_GPT_FAST_MODE;
    else process.env.PI_GPT_FAST_MODE = previousHandoff;
  }
});
