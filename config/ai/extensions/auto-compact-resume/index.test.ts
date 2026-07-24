import { describe, expect, test } from "bun:test";

const modulePath = "./index.ts";

type Handler = (event: any, context: any) => void | Promise<void>;

async function setup() {
  const extension = await import(modulePath).catch(() => null);
  expect(extension).not.toBeNull();
  if (!extension) throw new Error("extension module is missing");

  const handlers = new Map<string, Handler[]>();
  const sent: Array<{ message: any; options: any }> = [];
  const pi = {
    on(event: string, handler: Handler) {
      handlers.set(event, [...(handlers.get(event) ?? []), handler]);
    },
    sendMessage(message: any, options: any) {
      sent.push({ message, options });
    },
  };

  extension.default(pi as any);

  return {
    extension,
    sent,
    async emit(event: string, payload: any, context: any) {
      for (const handler of handlers.get(event) ?? []) {
        await handler(payload, context);
      }
    },
  };
}

function makeContext(
  tokens: number | null,
  branch: any[] = [{ type: "message", id: "entry-1" }],
) {
  const compactions: any[] = [];
  const notifications: Array<{ message: string; level: string }> = [];
  let currentTokens = tokens;

  return {
    compactions,
    notifications,
    setTokens(value: number | null) {
      currentTokens = value;
    },
    context: {
      model: { maxTokens: 128_000 },
      sessionManager: { getBranch: () => branch },
      getContextUsage: () => ({
        tokens: currentTokens,
        contextWindow: 272_000,
        percent: currentTokens === null ? null : (currentTokens / 272_000) * 100,
      }),
      compact(options: any) {
        compactions.push(options);
      },
      hasUI: true,
      ui: {
        notify(message: string, level: string) {
          notifications.push({ message, level });
        },
      },
    },
  };
}

function assistantMessage(options: { toolCall?: boolean; stopReason?: string } = {}) {
  return {
    role: "assistant",
    stopReason: options.stopReason ?? (options.toolCall ? "toolUse" : "stop"),
    content: options.toolCall
      ? [{ type: "toolCall", id: "call-1", name: "read", arguments: {} }]
      : [{ type: "text", text: "response" }],
  };
}

describe("auto compact and resume", () => {
  test("reserves the full GPT-5.6 Sol output budget plus a safety margin", async () => {
    const { extension } = await setup();
    expect(extension.calculateThreshold(272_000, 128_000)).toBe(127_616);
  });

  test("leaves contexts below the safe threshold untouched", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(127_615);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ toolCall: true }) },
      context,
    );

    expect(compactions).toHaveLength(0);
  });

  test("compacts unfinished tool work once at the safe threshold", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(127_616);
    const event = { message: assistantMessage({ toolCall: true }) };

    await harness.emit("turn_end", event, context);
    await harness.emit("turn_end", event, context);

    expect(compactions).toHaveLength(1);
  });

  test("resumes unfinished work invisibly after successful compaction", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(130_000);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ toolCall: true }) },
      context,
    );
    compactions[0].onComplete({});

    expect(harness.sent).toHaveLength(1);
    expect(harness.sent[0]).toMatchObject({
      message: {
        customType: "auto-compact-resume",
        display: false,
        details: { automatic: true },
      },
      options: { triggerTurn: true, deliverAs: "followUp" },
    });
  });

  test("compacts a completed answer without manufacturing another turn", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(130_000);

    await harness.emit("turn_end", { message: assistantMessage() }, context);
    compactions[0].onComplete({});

    expect(compactions).toHaveLength(1);
    expect(harness.sent).toHaveLength(0);
  });

  test("resumes a response stopped by the output-length cutoff", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(269_000);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ stopReason: "length" }) },
      context,
    );
    compactions[0].onComplete({});

    expect(harness.sent).toHaveLength(1);
  });

  test("resumes a length-truncated response even when compaction is unnecessary", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(50_000);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ stopReason: "length" }) },
      context,
    );

    expect(compactions).toHaveLength(0);
    expect(harness.sent).toHaveLength(1);
  });

  test("resumes unfinished work when there is nothing to compact and defers another attempt", async () => {
    const harness = await setup();
    const { context, compactions, notifications, setTokens } = makeContext(130_000);
    const event = { message: assistantMessage({ toolCall: true }) };

    await harness.emit("turn_end", event, context);
    compactions[0].onError(new Error("Nothing to compact (session too small)"));

    expect(harness.sent).toHaveLength(1);
    expect(notifications).toHaveLength(0);

    await harness.emit("turn_start", {}, context);
    await harness.emit("turn_end", event, context);
    expect(compactions).toHaveLength(1);

    setTokens(130_000 + harness.extension.RETRY_GROWTH_TOKENS);
    await harness.emit("turn_start", {}, context);
    await harness.emit("turn_end", event, context);
    expect(compactions).toHaveLength(2);
  });

  test("resumes unfinished work after a transient compaction failure without a duplicate error", async () => {
    const harness = await setup();
    const { context, compactions, notifications } = makeContext(130_000);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ toolCall: true }) },
      context,
    );
    compactions[0].onError(new Error("provider unavailable"));

    expect(harness.sent).toHaveLength(1);
    expect(notifications).toHaveLength(0);
  });

  test("does not loop after a terminal authentication failure", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(130_000);

    await harness.emit(
      "turn_end",
      { message: assistantMessage({ toolCall: true }) },
      context,
    );
    compactions[0].onError(new Error("Authentication failed: credentials expired"));

    expect(harness.sent).toHaveLength(0);
  });

  test("compacts an already-large resumed session without starting work", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(130_000);

    await harness.emit("session_start", { reason: "resume" }, context);
    compactions[0].onComplete({});

    expect(compactions).toHaveLength(1);
    expect(harness.sent).toHaveLength(0);
  });

  test("does not immediately recompact a session whose leaf is a compaction", async () => {
    const harness = await setup();
    const { context, compactions } = makeContext(130_000, [
      { type: "compaction", id: "compaction-1" },
    ]);

    await harness.emit("session_start", { reason: "resume" }, context);

    expect(compactions).toHaveLength(0);
    expect(harness.sent).toHaveLength(0);
  });
});
