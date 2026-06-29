import http from "node:http";
import https from "node:https";
import tls from "node:tls";
import { responsesUrl } from "./config.js";

function normalizeProxyUrl(value) {
  const text = String(value || "").trim();
  if (!text) return "";
  return /^[a-z]+:\/\//i.test(text) ? text : `http://${text}`;
}

function proxyFor(config) {
  const proxy = normalizeProxyUrl(config.proxyUrl);
  if (!proxy) return null;
  const parsed = new URL(proxy);
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error(`Unsupported proxy protocol: ${parsed.protocol}`);
  }
  return parsed;
}

function collectResponse(response, onChunk) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    response.on("data", (chunk) => {
      chunks.push(chunk);
      if (onChunk) onChunk(chunk);
    });
    response.on("end", () => {
      resolve({
        ok: response.statusCode >= 200 && response.statusCode < 300,
        status: response.statusCode,
        headers: response.headers,
        text: Buffer.concat(chunks).toString("utf8")
      });
    });
    response.on("error", reject);
  });
}

function requestViaHttpProxy({ url, proxy, headers, body, timeoutMs, onChunk }) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const settleResolve = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };
    const settleReject = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(error);
    };
    const target = new URL(url);
    const proxyPort = Number(proxy.port || (proxy.protocol === "https:" ? 443 : 80));
    const connectOptions = {
      host: proxy.hostname,
      port: proxyPort,
      method: "CONNECT",
      path: `${target.hostname}:443`,
      headers: { host: `${target.hostname}:443` }
    };
    if (proxy.username || proxy.password) {
      const token = Buffer.from(`${decodeURIComponent(proxy.username)}:${decodeURIComponent(proxy.password)}`).toString("base64");
      connectOptions.headers["proxy-authorization"] = `Basic ${token}`;
    }

    let tunnelSocket;
    const connect = (proxy.protocol === "https:" ? https : http).request(connectOptions);
    const timer = setTimeout(() => {
      const error = new Error("Proxy request timed out");
      settleReject(error);
      connect.destroy(error);
      if (tunnelSocket) tunnelSocket.destroy(error);
    }, timeoutMs);

    connect.on("connect", (response, socket) => {
      if (response.statusCode !== 200) {
        socket.destroy();
        settleReject(new Error(`Proxy CONNECT HTTP ${response.statusCode}`));
        return;
      }
      tunnelSocket = socket;
      socket.on("error", (error) => settleReject(error));
      const request = https.request({
        host: target.hostname,
        servername: target.hostname,
        path: `${target.pathname}${target.search}`,
        method: "POST",
        headers,
        createConnection: () => tls.connect({ socket, servername: target.hostname }),
        agent: false
      }, async (apiResponse) => {
        try {
          const result = await collectResponse(apiResponse, onChunk);
          settleResolve(result);
        } catch (error) {
          settleReject(error);
        }
      });
      request.on("error", (error) => settleReject(error));
      request.write(body);
      request.end();
    });
    connect.on("error", (error) => settleReject(error));
    connect.end();
  });
}

async function postResponses(config, body, { stream = false, onChunk = null } = {}) {
  const url = responsesUrl(config.baseUrl);
  const bodyText = JSON.stringify(body);
  const headers = {
    "content-type": "application/json",
    authorization: `Bearer ${config.apiKey}`,
    "content-length": Buffer.byteLength(bodyText)
  };
  const proxy = proxyFor(config);
  if (proxy) {
    return requestViaHttpProxy({ url, proxy, headers, body: bodyText, timeoutMs: config.timeoutMs, onChunk });
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeoutMs);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: bodyText,
      signal: controller.signal
    });
    const text = await response.text();
    return {
      ok: response.ok,
      status: response.status,
      headers: Object.fromEntries(response.headers.entries()),
      text
    };
  } finally {
    clearTimeout(timer);
  }
}

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
    throw new Error("Missing API key. Set OPENAI_API_KEY or create %USERPROFILE%\\.codex\\auth.json with OPENAI_API_KEY.");
  }

  const body = {
    model: config.model,
    input: `${prompt.system}\n\n${prompt.user}`,
    text: { format: { type: "json_object" } },
    store: false
  };

  const effort = config.reasoningEffort.toLowerCase();
  if (["minimal", "low", "medium", "high"].includes(effort)) {
    body.reasoning = { effort };
  }

  {
    const response = await postResponses(config, body);
    const raw = response.text;
    if (!response.ok) {
      let detail = raw.slice(0, 500);
      try {
        const parsed = JSON.parse(raw);
        detail = parsed.message || parsed.error?.message || detail;
      } catch {
        // Keep raw detail.
      }
      if (response.status === 401) {
        detail += ". Set a valid OPENAI_API_KEY. Codex login tokens are not used as API keys.";
      }
      throw new Error(`API HTTP ${response.status}: ${detail}`);
    }

    const data = JSON.parse(raw);
    return normalizeResult(parseJsonObject(parseOutputText(data)));
  }
}

export async function requestCommandExtraction(config, { text, url = "", tool = "custom" } = {}) {
  if (!config.apiKey) {
    throw new Error("Missing API key. Set OPENAI_API_KEY or create %USERPROFILE%\\.codex\\auth.json with OPENAI_API_KEY.");
  }

  const input = [
    "你是命令文档整理助手。请从输入文档里提取可直接用于终端补全的常用命令。",
    "只输出 JSON，不要 Markdown。",
    "JSON 格式：{\"commands\":[{\"tool\":\"工具分类\",\"command\":\"命令模板\",\"summary\":\"一句中文用途说明\",\"aliases\":[],\"tags\":[],\"source\":\"ai-import\",\"sourceUrl\":\"来源URL\"}]}",
    "规则：",
    "1. command 必须是正确命令模板，可以使用 <服务名>、<命名空间> 这类占位符。",
    "2. 不要输出明显错误或拼接错的命令。",
    "3. summary 控制在 30 个中文以内。",
    "4. 优先提取查看、诊断、启动、停止、日志、连接、部署、构建这类高频命令。",
    "5. 最多返回 80 条。",
    `默认工具分类：${tool || "custom"}`,
    url ? `来源 URL：${url}` : "",
    "",
    String(text || "").slice(0, 60000)
  ].filter(Boolean).join("\n");

  const body = {
    model: config.model,
    input,
    text: { format: { type: "json_object" } },
    store: false
  };

  const effort = config.reasoningEffort.toLowerCase();
  if (["minimal", "low", "medium", "high"].includes(effort)) {
    body.reasoning = { effort };
  }

  const response = await postResponses(config, body);
  if (!response.ok) {
    throw new Error(`API HTTP ${response.status}: ${response.text.slice(0, 500)}`);
  }
  const data = JSON.parse(response.text);
  const parsed = parseJsonObject(parseOutputText(data));
  const commands = Array.isArray(parsed.commands) ? parsed.commands : [];
  return commands
    .map((entry) => ({
      tool: String(entry?.tool || tool || "custom").trim(),
      command: String(entry?.command || "").trim(),
      summary: String(entry?.summary || "").trim(),
      aliases: list(entry?.aliases),
      tags: list(entry?.tags),
      source: String(entry?.source || "ai-import").trim(),
      sourceUrl: String(entry?.sourceUrl || entry?.url || url || "").trim()
    }))
    .filter((entry) => entry.command && entry.summary)
    .slice(0, 80);
}

export async function requestCommandHelpTextStream(config, prompt, onText) {
  if (!config.apiKey) {
    throw new Error("Missing API key. Set OPENAI_API_KEY or create %USERPROFILE%\\.codex\\auth.json with OPENAI_API_KEY.");
  }

  const body = {
    model: config.model,
    input: `${prompt.system}\n\n${prompt.user}`,
    stream: true,
    store: false
  };
  const proxy = proxyFor(config);
  if (proxy) {
    const proxyConfig = { ...config, timeoutMs: Math.max(config.timeoutMs, 120000) };
    const response = await postResponses(proxyConfig, {
      model: config.model,
      input: `${prompt.system}\n\n${prompt.user}`,
      store: false
    });
    if (!response.ok) {
      throw new Error(`API HTTP ${response.status}: ${response.text.slice(0, 500)}`);
    }
    try {
      const parsed = JSON.parse(response.text);
      const text = parseOutputText(parsed);
      if (text) onText(text);
      return text;
    } catch {
      if (response.text) onText(response.text);
      return response.text;
    }
  }

  const response = await fetch(responsesUrl(config.baseUrl), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.apiKey}`
    },
    body: JSON.stringify(body)
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

function relatedCommands(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => {
      if (typeof item === "string") return { command: item, purpose: "", when: "" };
      if (!item || typeof item !== "object") return null;
      return {
        command: String(item.command || "").trim(),
        purpose: String(item.purpose || "").trim(),
        when: String(item.when || "").trim()
      };
    })
    .filter((item) => item?.command);
}

function normalizeResult(value) {
  const completions = list(value.completions);
  return {
    title: String(value.title || "\u547d\u4ee4\u52a9\u624b"),
    summary: String(value.summary || ""),
    confidence: String(value.confidence || "medium"),
    completion: String(value.completion || completions[0] || ""),
    completions,
    usage: list(value.usage),
    examples: examples(value.examples),
    related_commands: relatedCommands(value.related_commands),
    risks: list(value.risks),
    next_steps: list(value.next_steps)
  };
}
