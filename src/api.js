import { responsesUrl } from "./config.js";

function parseOutputText(data) {
  if (typeof data.output_text === "string" && data.output_text.trim()) return data.output_text;

  const parts = [];
  for (const item of data.output || []) {
    for (const content of item.content || []) {
      if (typeof content.text === "string") parts.push(content.text);
    }
  }
  return parts.join("\n").trim();
}

function parseJsonObject(text) {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) throw new Error("API response was not JSON.");
    return JSON.parse(match[0]);
  }
}

export async function requestCommandHelp(config, prompt) {
  if (!config.apiKey) {
    throw new Error("Missing API key. Set OPENAI_API_KEY or create %USERPROFILE%\\.codex\\auth.json.");
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeoutMs);
  const body = {
    model: config.model,
    input: [
      { role: "system", content: [{ type: "input_text", text: prompt.system }] },
      { role: "user", content: [{ type: "input_text", text: prompt.user }] }
    ],
    text: { format: { type: "json_object" } }
  };

  const effort = config.reasoningEffort.toLowerCase();
  if (["minimal", "low", "medium", "high"].includes(effort)) {
    body.reasoning = { effort };
  }

  try {
    const response = await fetch(responsesUrl(config.baseUrl), {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${config.apiKey}`
      },
      body: JSON.stringify(body),
      signal: controller.signal
    });

    const raw = await response.text();
    if (!response.ok) {
      let detail = raw.slice(0, 500);
      try {
        const parsed = JSON.parse(raw);
        detail = parsed.message || parsed.error?.message || detail;
      } catch {
        // Keep raw detail.
      }
      if (response.status === 401) {
        detail += "。请设置有效的 OPENAI_API_KEY；Codex 登录 token 通常不能当作 API key 使用。";
      }
      throw new Error(`API HTTP ${response.status}: ${detail}`);
    }

    const data = JSON.parse(raw);
    return normalizeResult(parseJsonObject(parseOutputText(data)));
  } finally {
    clearTimeout(timer);
  }
}

function list(value) {
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (!value) return [];
  return [String(value)];
}

function examples(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => {
      if (typeof item === "string") return { command: item, purpose: "" };
      if (!item || typeof item !== "object") return null;
      return {
        command: String(item.command || "").trim(),
        purpose: String(item.purpose || "").trim()
      };
    })
    .filter((item) => item?.command);
}

function normalizeResult(value) {
  return {
    title: String(value.title || "命令助手"),
    summary: String(value.summary || ""),
    confidence: String(value.confidence || "medium"),
    completion: String(value.completion || ""),
    usage: list(value.usage),
    examples: examples(value.examples),
    risks: list(value.risks),
    next_steps: list(value.next_steps)
  };
}
