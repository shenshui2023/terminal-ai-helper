import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { requestCommandHelp } from "./api.js";
import { buildPrompt } from "./prompts.js";
import { renderHuman, renderJson, renderRaw } from "./render.js";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 128 * 1024) {
        reject(new Error("Request body is too large."));
        req.destroy();
      }
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function send(res, status, contentType, body) {
  res.writeHead(status, {
    "content-type": contentType,
    "cache-control": "no-store",
    "access-control-allow-origin": "*"
  });
  res.end(body);
}

function userHome() {
  return process.env.USERPROFILE || os.homedir();
}

function sanitizePanelId(value) {
  return String(value || "remote")
    .replace(/[^a-zA-Z0-9_.-]+/g, "-")
    .slice(0, 80) || "remote";
}

function isProcessAlive(pid) {
  const value = Number(pid);
  if (!Number.isInteger(value) || value <= 0) return false;
  try {
    process.kill(value, 0);
    return true;
  } catch {
    return false;
  }
}

function openPanelFromServer({ mode, text, source, shell, session }) {
  if (process.platform !== "win32") {
    throw new Error("panel mode is only supported on local Windows.");
  }

  const panelScript = path.join(rootDir, "powershell", "panel.ps1");
  if (!fs.existsSync(panelScript)) {
    throw new Error(`panel script not found: ${panelScript}`);
  }

  const panelDir = path.join(userHome(), ".terminal-ai-helper", "panels");
  fs.mkdirSync(panelDir, { recursive: true });
  const panelId = `remote-${sanitizePanelId(session || shell || source || "ssh")}`;
  const inputFile = path.join(os.tmpdir(), `taih-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`);
  fs.writeFileSync(inputFile, text, "utf8");

  const commandFile = path.join(panelDir, `${panelId}.command.json`);
  const pidFile = path.join(panelDir, `${panelId}.pid`);
  fs.writeFileSync(commandFile, JSON.stringify({
    inputFile,
    mode,
    source: source || "ssh-remote-panel",
    shell: shell || "ssh remote shell",
    at: new Date().toISOString()
  }), "utf8");

  let existingPid = "";
  try {
    existingPid = fs.readFileSync(pidFile, "utf8").trim();
  } catch {
    existingPid = "";
  }
  if (isProcessAlive(existingPid)) {
    return { opened: false, reused: true, panelId };
  }

  const child = spawn("powershell", [
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", panelScript,
    "-InputFile", inputFile,
    "-Mode", mode,
    "-PanelId", panelId,
    "-AnchorX", "-1",
    "-AnchorY", "-1",
    "-AnchorW", "-1",
    "-AnchorH", "-1"
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  });
  child.unref();
  return { opened: true, reused: false, panelId };
}

export async function startServer({ config, port }) {
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method === "GET" && req.url === "/health") {
        send(res, 200, "application/json; charset=utf-8", JSON.stringify({ ok: true }));
        return;
      }

      if (req.method !== "POST" || !["/api", "/panel"].includes(req.url)) {
        send(res, 404, "text/plain; charset=utf-8", "not found");
        return;
      }

      const body = JSON.parse(await readBody(req));
      const mode = body.mode || "explain";
      const text = String(body.text || "").trim();
      const format = body.format || "text";
      if (!["explain", "complete", "fix"].includes(mode)) {
        send(res, 400, "text/plain; charset=utf-8", "invalid mode");
        return;
      }
      if (!text) {
        send(res, 400, "text/plain; charset=utf-8", "empty text");
        return;
      }

      if (req.url === "/panel") {
        const result = openPanelFromServer({
          mode,
          text,
          source: body.source || "ssh-remote-panel",
          shell: body.shell || "ssh remote shell",
          session: body.session || body.host || "ssh"
        });
        send(res, 200, "application/json; charset=utf-8", JSON.stringify({ ok: true, ...result }));
        return;
      }

      const prompt = buildPrompt({
        mode,
        text,
        source: body.source || "http",
        shell: body.shell || "ssh remote shell"
      });
      const result = await requestCommandHelp(config, prompt);
      const output = format === "json" ? renderJson(result) : format === "raw" ? renderRaw(result) : renderHuman(result);
      send(res, 200, format === "json" ? "application/json; charset=utf-8" : "text/plain; charset=utf-8", output);
    } catch (error) {
      send(res, 500, "text/plain; charset=utf-8", error.message);
    }
  });

  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  console.log(`terminal-ai-helper server listening on http://127.0.0.1:${port}`);
  console.log("Use SSH reverse tunnel: ssh -R 17888:127.0.0.1:17888 <user>@<host>");
}
