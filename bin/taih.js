#!/usr/bin/env node
import { loadConfig } from "../src/config.js";
import { requestCommandHelp, requestCommandHelpTextStream } from "../src/api.js";
import { buildPlainPrompt, buildPrompt } from "../src/prompts.js";
import { renderHuman, renderJson, renderRaw } from "../src/render.js";
import { readClipboard, writeClipboard } from "../src/clipboard.js";
import { appendHistory, clearCache, getCache, readHistory, setCache } from "../src/store.js";

const args = process.argv.slice(2);

function usage() {
  return `Usage:
  taih explain <command...>          Explain usage, risks, examples
  taih complete [--json] <prefix...> Suggest completions for current command
  taih fix [--json] <error...>       Explain an error and propose a fix
  taih clipboard [mode]              Read clipboard and run explain/complete/fix
  taih serve [--port 17888]          Run local HTTP helper for SSH reverse tunnels
  taih history [--json]              Show recent command help history
  taih cache clear                   Clear local response cache
  taih doctor                        Check local configuration

Options:
  --clipboard                        Use clipboard text when no command text is provided
  --copy                             Copy rendered output to clipboard
  --json                             Print structured JSON
  --no-cache                         Skip cache for this request
  --raw                              Print only completion text, useful for shell integration
  --stream                           Stream plain text output when the API supports SSE

Environment:
  TAIH_BASE_URL        API base URL, default https://qyapi.cjyyswq.com
  TAIH_MODEL           Model name, default gpt-5.5
  OPENAI_API_KEY       API key; otherwise read %USERPROFILE%\\.codex\\auth.json
`;
}

function takeFlag(name) {
  const index = args.indexOf(name);
  if (index === -1) return false;
  args.splice(index, 1);
  return true;
}

function takeOption(name, fallback) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  const value = args[index + 1];
  args.splice(index, value === undefined ? 1 : 2);
  return value ?? fallback;
}

async function readStdinIfPiped() {
  if (process.stdin.isTTY) return "";
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data.trim();
}

async function main() {
  const asJson = takeFlag("--json");
  const asRaw = takeFlag("--raw");
  const noCache = takeFlag("--no-cache");
  const stream = takeFlag("--stream");
  const copyOutput = takeFlag("--copy");
  let fromClipboard = takeFlag("--clipboard");
  const port = Number(takeOption("--port", process.env.TAIH_PORT || 17888));
  let mode = args.shift();
  const separator = args.indexOf("--");
  if (separator !== -1) args.splice(separator, 1);
  const config = loadConfig();

  if (!mode || mode === "-h" || mode === "--help") {
    console.log(usage());
    return;
  }

  if (mode === "clipboard") {
    fromClipboard = true;
    mode = args.shift() || "explain";
  }

  if (mode === "serve") {
    const { startServer } = await import("../src/server.js");
    await startServer({ config, port });
    return;
  }

  if (mode === "history") {
    const items = readHistory();
    console.log(asJson ? JSON.stringify(items, null, 2) : items.map((item, index) => {
      const text = String(item.text || "").replace(/\s+/g, " ").slice(0, 100);
      return `${index + 1}. [${item.mode}] ${text}`;
    }).join("\n"));
    return;
  }

  if (mode === "cache") {
    const sub = args.shift();
    if (sub === "clear") {
      clearCache();
      console.log("Cache cleared.");
      return;
    }
    console.error("Usage: taih cache clear");
    process.exitCode = 2;
    return;
  }

  if (mode === "doctor") {
    console.log("terminal-ai-helper doctor");
    console.log(`  baseUrl: ${config.baseUrl}`);
    console.log(`  model: ${config.model}`);
    console.log(`  apiKey: ${config.apiKey ? "found" : "missing"}`);
    console.log(`  authSource: ${config.authSource}`);
    if (!config.apiKey) process.exitCode = 2;
    return;
  }

  if (!["explain", "complete", "fix"].includes(mode)) {
    console.error(`Unknown mode: ${mode}\n`);
    console.error(usage());
    process.exitCode = 2;
    return;
  }

  const stdin = await readStdinIfPiped();
  let source = stdin ? "stdin" : "arguments";
  let text = [...args, stdin].filter(Boolean).join(" ").trim();
  if (!text && fromClipboard) {
    text = readClipboard();
    source = "clipboard";
  }

  if (!text) {
    console.error("No command text provided.");
    process.exitCode = 2;
    return;
  }

  const shell = process.env.TAIH_SHELL || process.env.ComSpec || "terminal";
  if (stream && !asJson && !asRaw) {
    const prompt = buildPlainPrompt({ mode, text, source, shell });
    const started = Date.now();
    let full = "";
    full = await requestCommandHelpTextStream(config, prompt, (chunk) => process.stdout.write(chunk));
    if (!full.endsWith("\n")) process.stdout.write("\n");
    appendHistory({ mode, text, source, cacheHit: false, title: "stream", summary: `streamed in ${((Date.now() - started) / 1000).toFixed(1)}s` });
    return;
  }

  const prompt = buildPrompt({ mode, text, source, shell });
  let result = noCache ? null : getCache(mode, text);
  const cacheHit = Boolean(result);
  if (!result) {
    result = await requestCommandHelp(config, prompt);
    if (mode !== "complete") setCache(mode, text, result);
  }
  appendHistory({ mode, text, source, cacheHit, title: result.title, summary: result.summary });

  const output = asRaw ? renderRaw(result) : asJson ? renderJson(result) : renderHuman(result);
  if (copyOutput) writeClipboard(output);
  console.log(output);
}

main().catch((error) => {
  console.error(`terminal-ai-helper failed: ${error.message}`);
  if (process.env.TAIH_DEBUG) console.error(error.stack);
  process.exitCode = 1;
});
