// @ts-nocheck
// Report the context usage to the herdr sidebar after every turn (see dotfiles config/herdr/pi-ctx.sh).
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const script = path.join(os.homedir(), "dotfiles/config/herdr/pi-ctx.sh");

export default function (pi) {
  const report = (_event, ctx) => {
    const u = ctx.getContextUsage?.();
    if (!u || u.percent == null) return;
    try {
      spawn(script, [String(u.percent)], { stdio: "ignore", detached: true }).on("error", () => {}).unref();
    } catch {}
  };
  pi.on("session_start", report);
  pi.on("turn_end", report);
  pi.on("agent_end", report);
}
