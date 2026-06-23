import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { requestCommandHelp } from "../core/api.js";
import { buildPrompt } from "../ai/prompts.js";
import { renderHuman, renderJson, renderRaw } from "../core/render.js";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

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

function openLogFile(name) {
  const logDir = path.join(userHome(), ".terminal-ai-helper", "logs");
  fs.mkdirSync(logDir, { recursive: true });
  const logFile = path.join(logDir, `${name}.log`);
  return fs.openSync(logFile, "a");
}

function findWindowsPortOwner(port) {
  if (process.platform !== "win32") return 0;
  try {
    const output = execFileSync("powershell", [
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-Command",
      `(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort ${Number(port)} -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)`
    ], {
      encoding: "utf8",
      windowsHide: true,
      stdio: ["ignore", "pipe", "ignore"]
    }).trim();
    const pid = Number(output);
    return Number.isInteger(pid) && pid > 0 ? pid : 0;
  } catch {
    return 0;
  }
}

async function wait(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function replaceExistingServer(port) {
  const pid = findWindowsPortOwner(port);
  if (!pid || pid === process.pid) {
    throw new Error(`port ${port} is already in use, but no replaceable owner process was found.`);
  }
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    try {
      execFileSync("taskkill", ["/PID", String(pid), "/F"], { windowsHide: true, stdio: "ignore" });
    } catch (error) {
      throw new Error(`failed to stop existing server process ${pid}: ${error.message}`);
    }
  }
  for (let index = 0; index < 20; index += 1) {
    await wait(150);
    if (!findWindowsPortOwner(port)) return pid;
  }
  throw new Error(`existing server process ${pid} did not release port ${port}.`);
}

function openPanelFromServer({ mode, text, source, shell, session, tools, style }) {
  if (process.platform !== "win32") {
    throw new Error("panel mode is only supported on local Windows.");
  }

  const panelScript = path.join(rootDir, "apps", "powershell", "panel.ps1");
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
    tools: tools || "auto",
    style: style || "brief",
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

  const outLog = openLogFile(`${panelId}.out`);
  const errLog = openLogFile(`${panelId}.err`);
  const child = spawn("powershell.exe", [
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", panelScript,
    "-InputFile", inputFile,
    "-Mode", mode,
    "-Tools", tools || "auto",
    "-PanelId", panelId,
    "-AnchorX", "-1",
    "-AnchorY", "-1",
    "-AnchorW", "-1",
    "-AnchorH", "-1"
  ], {
    cwd: rootDir,
    detached: false,
    stdio: ["ignore", outLog, errLog],
    windowsHide: false
  });
  return { opened: true, reused: false, panelId, childPid: child.pid || 0 };
}

function runCompletionPopupFromServer({ text, tools, style, hint, noDialog, waitAi, session, shell, source }) {
  if (process.platform !== "win32") {
    throw new Error("completion popup is only supported on local Windows.");
  }

  const popupScript = path.join(rootDir, "apps", "powershell", "complete-popup.ps1");
  if (!fs.existsSync(popupScript)) {
    throw new Error(`completion popup script not found: ${popupScript}`);
  }

  return new Promise((resolve, reject) => {
    const panelId = `remote-${sanitizePanelId(session || shell || source || "ssh")}`;
    const args = [
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", popupScript,
      "-Prefix", text,
      "-Tools", tools || "auto",
      "-Style", style || "brief",
      "-Hint", hint || "",
      "-PanelId", panelId,
      "-AnchorX", "-1",
      "-AnchorY", "-1",
      "-AnchorW", "-1",
      "-AnchorH", "-1"
    ];
    if (noDialog) args.push("-NoDialog");
    if (waitAi) args.push("-WaitAi");

    const child = spawn("powershell", args, {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: false
    });
    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => {
      try { child.kill(); } catch {
        // Ignore kill failures.
      }
      reject(new Error("completion popup timed out."));
    }, 10 * 60 * 1000);

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      const raw = stdout.trim();
      if (code !== 0) {
        reject(new Error((stderr || raw || `completion popup exited with code ${code}`).trim()));
        return;
      }
      if (!raw) {
        resolve({ ok: false, completion: "", source: "empty" });
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        resolve({ ok: true, completion: raw, source: "stdout" });
      }
    });
  });
}

function toolMenuText(tools) {
  return `Generate a common command menu for the ${tools || "auto"} toolset.`;
}

export async function startServer({ config, port, replaceExisting = false }) {
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method === "GET" && req.url === "/health") {
        send(res, 200, "application/json; charset=utf-8", JSON.stringify({ ok: true }));
        return;
      }

      if (req.method !== "POST" || !["/api", "/panel", "/complete-popup"].includes(req.url)) {
        send(res, 404, "text/plain; charset=utf-8", "not found");
        return;
      }

      const body = JSON.parse(await readBody(req));
      const mode = body.mode || "explain";
      const text = String(body.text || "").trim();
      const format = body.format || "text";
      if (!["explain", "complete", "fix", "tools"].includes(mode)) {
        send(res, 400, "text/plain; charset=utf-8", "invalid mode");
        return;
      }
      if (!text && mode !== "tools") {
        send(res, 400, "text/plain; charset=utf-8", "empty text");
        return;
      }
      const requestText = text || toolMenuText(body.tools || "auto");

      if (req.url === "/panel") {
        const result = openPanelFromServer({
          mode,
          text: requestText,
          source: body.source || "ssh-remote-panel",
          shell: body.shell || "ssh remote shell",
          session: body.session || body.host || "ssh",
          tools: body.tools || "auto",
          style: body.style || "brief"
        });
        send(res, 200, "application/json; charset=utf-8", JSON.stringify({ ok: true, ...result }));
        return;
      }

      if (req.url === "/complete-popup") {
        const result = await runCompletionPopupFromServer({
          text: requestText,
          tools: body.tools || "auto",
          style: body.style || "brief",
          hint: body.extraInstructions || body.hint || "",
          session: body.session || body.host || "ssh",
          shell: body.shell || "ssh remote shell",
          source: body.source || "ssh-readline-complete-popup",
          noDialog: Boolean(body.noDialog),
          waitAi: Boolean(body.waitAi)
        });
        send(res, 200, "application/json; charset=utf-8", JSON.stringify(result));
        return;
      }

      const prompt = buildPrompt({
        mode,
        text: requestText,
        source: body.source || "http",
        shell: body.shell || "ssh remote shell",
        outputStyle: body.style || "standard",
        extraInstructions: body.extraInstructions || "",
        tools: body.tools || "auto"
      });
      const result = await requestCommandHelp(config, prompt);
      const output = format === "json" ? renderJson(result) : format === "raw" ? renderRaw(result) : renderHuman(result, { style: body.style || "standard" });
      send(res, 200, format === "json" ? "application/json; charset=utf-8" : "text/plain; charset=utf-8", output);
    } catch (error) {
      send(res, 500, "text/plain; charset=utf-8", error.message);
    }
  });

  let replacedPid = 0;
  await new Promise((resolve, reject) => {
    server.once("error", (error) => {
      if (error.code === "EADDRINUSE") {
        if (!replaceExisting) {
          console.log(`terminal-ai-helper server already listening on http://127.0.0.1:${port}`);
          console.log(`After updating the project, restart it with: node bin/taih.js serve --port ${port} --replace`);
          resolve();
          return;
        }
        replaceExistingServer(port).then((pid) => {
          replacedPid = pid;
          server.listen(port, "127.0.0.1", resolve);
        }).catch(reject);
        return;
      }
      reject(error);
    });
    server.listen(port, "127.0.0.1", resolve);
  });
  if (replacedPid) {
    console.log(`terminal-ai-helper replaced existing server process ${replacedPid}`);
  }
  if (server.listening) {
    console.log(`terminal-ai-helper server listening on http://127.0.0.1:${port}`);
  }
  console.log("Use SSH reverse tunnel: ssh -R 17888:127.0.0.1:17888 <user>@<host>");
}
