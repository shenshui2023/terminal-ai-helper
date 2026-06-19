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
        detail += ". Set a valid OPENAI_API_KEY. Codex login tokens usually cannot be used as API keys.";
      }
      throw new Error(`API HTTP ${response.status}: ${detail}`);
    }

    const data = JSON.parse(raw);
    return normalizeResult(parseJsonObject(parseOutputText(data)));
  } finally {
    clearTimeout(timer);
  }
}

export async function requestCommandHelpTextStream(config, prompt, onText) {
  if (!config.apiKey) {
    throw new Error("Missing API key. Set OPENAI_API_KEY or create %USERPROFILE%\\.codex\\auth.json.");
  }

  const response = await fetch(responsesUrl(config.baseUrl), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.apiKey}`
    },
    body: JSON.stringify({
      model: config.model,
      input: [
        { role: "system", content: [{ type: "input_text", text: prompt.system }] },
        { role: "user", content: [{ type: "input_text", text: prompt.user }] }
      ],
      stream: true
    })
  });

  if (!response.ok) {
    throw new Error(`API HTTP ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }

  const contentType = response.headers.get("content-type") || "";
  if (!contentType.includes("text/event-stream")) {
    const raw = await response.text();
    try {
      const parsed = JSON.parse(raw);
      const text = parseOutputText(parsed);
      if (text) onText(text);
      return text;
    } catch {
      if (raw) onText(raw);
      return raw;
    }
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let full = "";

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split(/\r?\n\r?\n/);
    buffer = events.pop() || "";

    for (const event of events) {
      for (const line of event.split(/\r?\n/)) {
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (!data || data === "[DONE]") continue;
        try {
          const parsed = JSON.parse(data);
          const eventType = String(parsed.type || "");
          const delta = eventType.includes("delta")
            ? (parsed.delta || parsed.text || "")
            : (parsed.delta && !parsed.response ? parsed.delta : "");
          if (typeof delta === "string" && delta) {
            full += delta;
            onText(delta);
          }
        } catch {
          // Ignore non-JSON stream keepalives.
        }
      }
    }
  }

  return full;
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
    title: String(value.title || "\u547d\u4ee4\u52a9\u624b"),
    summary: String(value.summary || ""),
    confidence: String(value.confidence || "medium"),
    completion: String(value.completion || ""),
    usage: list(value.usage),
    examples: examples(value.examples),
    risks: list(value.risks),
    next_steps: list(value.next_steps)
  };
}
