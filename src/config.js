import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

function readCodexAuth() {
  const authPath = path.join(os.homedir(), ".codex", "auth.json");
  try {
    const raw = fs.readFileSync(authPath, "utf8");
    const parsed = JSON.parse(raw);
    if (typeof parsed.OPENAI_API_KEY === "string" && parsed.OPENAI_API_KEY.trim()) {
      return { key: parsed.OPENAI_API_KEY.trim(), source: authPath };
    }
  } catch {
    // Missing or invalid auth.json is fine; environment variables may be used.
  }
  return { key: "", source: "not found" };
}

function readWindowsUserEnv(name) {
  if (process.platform !== "win32") return { value: "", source: "not found" };
  try {
    const output = execFileSync("reg.exe", ["query", "HKCU\\Environment", "/v", name], {
      encoding: "utf8",
      windowsHide: true,
      stdio: ["ignore", "pipe", "ignore"]
    });
    const line = output.split(/\r?\n/).find((item) => item.trim().startsWith(name));
    const match = line?.match(new RegExp(`^\\s*${name}\\s+REG_\\w+\\s+(.+)$`));
    const value = match?.[1]?.trim() || "";
    return value ? { value, source: `HKCU\\Environment:${name}` } : { value: "", source: "not found" };
  } catch {
    return { value: "", source: "not found" };
  }
}

export function loadConfig() {
  const auth = readCodexAuth();
  const userApiKey = readWindowsUserEnv("OPENAI_API_KEY");
  const apiKey = process.env.OPENAI_API_KEY || userApiKey.value || auth.key;
  const authSource = process.env.OPENAI_API_KEY ? "OPENAI_API_KEY" : userApiKey.value ? userApiKey.source : auth.source;
  return {
    baseUrl: process.env.TAIH_BASE_URL || "https://qyapi.cjyyswq.com",
    model: process.env.TAIH_MODEL || "gpt-5.5",
    apiKey,
    authSource,
    timeoutMs: Number(process.env.TAIH_TIMEOUT_MS || 30000),
    reasoningEffort: process.env.TAIH_REASONING_EFFORT || ""
  };
}

export function responsesUrl(baseUrl) {
  const clean = baseUrl.replace(/\/+$/, "");
  if (clean.endsWith("/v1")) return `${clean}/responses`;
  if (clean.endsWith("/responses")) return clean;
  return `${clean}/v1/responses`;
}
