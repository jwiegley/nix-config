import { spawnSync } from "node:child_process";
import { TmuxMultiplexer } from "__SUBAGENTURA_ROOT__/src/nix-tmux-test-bundle.js";

const socket = process.env.PI_SUBAGENTURA_TMUX_SOCKET;
if (!socket) throw new Error("PI_SUBAGENTURA_TMUX_SOCKET is required");
delete process.env.TMUX;
delete process.env.TMUX_PANE;

const tmux = new TmuxMultiplexer();
if (!tmux.isAvailable()) throw new Error("tmux is unavailable on the declarative PATH");

let paneId: string | undefined;
try {
  const pane = tmux.createPane({
    name: "Nix Integration",
    cwd: process.cwd(),
    background: true,
    id: "deadbeef",
  });
  paneId = pane.paneId;
  if (!paneId.startsWith("%") || !tmux.isPaneAlive(paneId)) {
    throw new Error(`tmux pane did not become live: ${paneId}`);
  }
  const commands = tmux.buildAttachCommands({
    paneId,
    windowName: pane.windowName,
  });
  if (!commands.attachCommand.includes("pi-subagent-deadbeef")) {
    throw new Error(`detached attach command is wrong: ${commands.attachCommand}`);
  }
  tmux.sendKeys(paneId, "printf subagentura-tmux-ok");
  tmux.sendEnter(paneId);
  tmux.killPane(paneId);
  if (tmux.isPaneAlive(paneId)) throw new Error("cancelled tmux pane remains alive");
} finally {
  spawnSync("tmux", ["-L", socket, "kill-server"], { stdio: "ignore" });
}

const status = spawnSync("tmux", ["-L", socket, "list-sessions"], {
  stdio: "ignore",
});
if (status.status === 0) throw new Error("isolated tmux server survived cleanup");

console.log("subagentura-tmux-contract-ok");
