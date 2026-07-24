import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { TmuxMultiplexer } from "__SUBAGENTURA_ROOT__/src/nix-tmux-test-bundle.js";

const socket = process.env.PI_SUBAGENTURA_TMUX_SOCKET;
const marker = process.env.PI_SUBAGENTURA_TMUX_MARKER;
if (!socket) throw new Error("PI_SUBAGENTURA_TMUX_SOCKET is required");
if (!marker) throw new Error("PI_SUBAGENTURA_TMUX_MARKER is required");
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
  const quotedMarker = `'${marker.replace(/'/g, `'\\''`)}'`;
  tmux.sendKeys(paneId, `printf subagentura-tmux-ok > ${quotedMarker}`);
  tmux.sendEnter(paneId);
  for (let attempt = 0; attempt < 50 && !existsSync(marker); attempt += 1) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
  }
  if (!existsSync(marker) || readFileSync(marker, "utf8") !== "subagentura-tmux-ok") {
    throw new Error("tmux pane did not execute the delivered command");
  }
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
