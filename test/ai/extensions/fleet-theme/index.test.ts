import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import { describe, expect, test } from "bun:test";

const modulePath = "../../../../config/ai/extensions/fleet-theme/index.ts";
const expectedHash = "03ecec59f47f49b6562f95101d58ae6338377e0d9b84b6410e065f28e2c18d5a";

type Handler = (event: unknown, context: any) => unknown;

async function setup() {
  const extension = await import(modulePath);
  const handlers = new Map<string, Handler[]>();
  extension.default({
    on(event: string, handler: Handler) {
      handlers.set(event, [...(handlers.get(event) ?? []), handler]);
    },
  } as any);

  return {
    extension,
    emit(event: string, payload: unknown, context: any) {
      return (handlers.get(event) ?? []).map((handler) => handler(payload, context));
    },
  };
}

describe("fleet theme", () => {
  test("discovers the immutable theme oracle", async () => {
    const harness = await setup();
    const [resources] = harness.emit("resources_discover", {}, {});
    expect(resources).toEqual({ themePaths: [harness.extension.FLEET_THEME_PATH] });
    expect(harness.extension.FLEET_THEME_PATH).toEndWith(
      "/themes/dark-tool-backgrounds.json",
    );
    expect(
      createHash("sha256")
        .update(readFileSync(harness.extension.FLEET_THEME_PATH))
        .digest("hex"),
    ).toBe(expectedHash);
  });

  test("selects the theme only in an interactive TUI", async () => {
    for (const [mode, hasUI, expectedCalls] of [
      ["tui", true, 1],
      ["tui", false, 0],
      ["rpc", true, 0],
      ["json", true, 0],
      ["print", true, 0],
    ] as const) {
      const harness = await setup();
      const selected: string[] = [];
      harness.emit("session_start", {}, {
        mode,
        hasUI,
        ui: { setTheme: (name: string) => selected.push(name) },
      });
      expect(selected).toEqual(
        expectedCalls === 1 ? [harness.extension.FLEET_THEME_NAME] : [],
      );
    }
  });
});
