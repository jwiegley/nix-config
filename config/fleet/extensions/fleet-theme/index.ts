import { fileURLToPath } from "node:url";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const FLEET_THEME_NAME = "dark-tool-backgrounds";
export const FLEET_THEME_PATH = fileURLToPath(
  new URL("../../themes/dark-tool-backgrounds.json", import.meta.url),
);

export default function fleetTheme(pi: ExtensionAPI) {
  pi.on("resources_discover", () => ({ themePaths: [FLEET_THEME_PATH] }));
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode === "tui" && ctx.hasUI) {
      ctx.ui.setTheme(FLEET_THEME_NAME);
    }
  });
}
