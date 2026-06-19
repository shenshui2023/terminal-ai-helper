import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function readCodexAuth() {
  const authPath = path.join(os.homedir(), ".codex", "auth.json");
  try {
    const raw = fs.readFileSync(authPath, "utf8");
    const parsed = JSON.parse(raw);
    if (typeof parsed.OPENAI_API_KEY === "string" && parsed.OPENAI_API_KEY.trim()) {
      return { key: parsed.OPENAI_API_KEY.trim(), source: authPath };
    }
    if (typeof parsed.tokens?.access_token === "string" && parsed.tokens.access_token.trim()) {
      return { key: parsed.tokens.access_token.trim(), source: `${authPath}:tokens.access_token` };
    }
  } catch {
    // Missing or invalid auth.json is fine; environment variables may be used.
  }
  return { key: "", source: "not found" };
}

export function loadConfig() {
  const auth = readCodexAuth();
  const apiKey = process.env.OPENAI_API_KEY || auth.key;
  return {
    baseUrl: process.env.TAIH_BASE_URL || "https://qyapi.cjyyswq.com",
    model: process.env.TAIH_MODEL || "gpt-5.5",
    apiKey,
    authSource: process.env.OPENAI_API_KEY ? "OPENAI_API_KEY" : auth.source,
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
