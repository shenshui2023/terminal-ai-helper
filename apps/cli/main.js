#!/usr/bin/env node
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { loadConfig } from "../../src/core/config.js";
import { requestCommandExtraction, requestCommandHelp, requestCommandHelpTextStream } from "../../src/core/api.js";
import { buildPlainPrompt, buildPrompt } from "../../src/ai/prompts.js";
import { renderHuman, renderJson, renderRaw } from "../../src/core/render.js";
import { readClipboard, writeClipboard } from "../../src/core/clipboard.js";
import { appendHistory, cacheStats, clearCache, getCache, readHistory, setCache } from "../../src/core/store.js";
import { getLocalHelp } from "../../src/knowledge/local-help.js";
import { commandCacheEntries } from "../../src/knowledge/command-cache.js";
import { addUserCommand, deleteUserCommand, importUserCommands, userCommandCachePath } from "../../src/knowledge/user-command-cache.js";

const args = process.argv.slice(2);
const validModes = new Set(["explain", "complete", "fix", "tools"]);

function usage() {
  return `用法:
  taih explain <命令...>             解析命令用法、风险、示例和相关命令
  taih complete [--json] <前缀...>   根据当前输入补全命令
  taih fix [--json] <报错...>        诊断报错并给出修复建议
  taih tools [描述...]               生成常用工具命令菜单
  taih clipboard [模式]              读取剪贴板并执行 explain/complete/fix/tools
  taih serve [--port 17888] [--replace]
                                      启动本地 HTTP helper，供 SSH 反向隧道使用
  taih history [--json]              查看最近的命令帮助历史
  taih cache clear                   清理本地缓存
  taih cache stats                   查看缓存和历史占用
  taih commands list [--json]        查看内置和用户命令一级缓存
  taih commands add --tool <分类> --command <命令> --summary <说明>
                                      手动新增一条用户命令
  taih commands delete --command <命令>
                                      删除一条用户命令
  taih commands import --from-file <文件> [--url <官网URL>]
                                      让中转站从文档里提取命令并写入用户缓存
  taih config get                    查看当前配置
  taih config set model <模型名>      写入用户级模型配置
  taih config set base-url <地址>     写入用户级接口地址
  taih config set timeout <毫秒>      写入用户级超时时间
  taih doctor                        检查本地配置
选项:
  --clipboard                        没有命令文本时读取剪贴板
  --copy                             把渲染后的结果复制到剪贴板
  --json                             输出结构化 JSON
  --no-cache                         本次请求跳过缓存
  --raw                              只输出补全文本，方便 shell 集成
  --stream                           API 支持 SSE 时流式输出纯文本
  --style <brief|standard|examples|custom>
                                      控制输出格式，面板默认使用 brief
  --tools <auto|linux,k8s,docker,...>
                                      指定工具集，用于解析、补全和工具菜单
  --instructions-file <文件>          追加自定义输出规则或提示词
  --replace                          serve 时替换已经占用该端口的旧 helper server
环境变量:
  TAIH_BASE_URL        API 地址，默认 https://qyapi.cjyyswq.com
  TAIH_MODEL           模型名，默认 gpt-5.5
  TAIH_TOOLS           默认工具集，例如 linux,k8s,ssh
  OPENAI_API_KEY       API key；也会检查 Windows 用户环境变量和 %USERPROFILE%\\.codex\\auth.json
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

function readInstructions(filePath) {
  if (!filePath) return "";
  return fs.readFileSync(filePath, "utf8").trim();
}

function setUserEnv(name, value) {
  if (process.platform !== "win32") {
    throw new Error("config set 目前只支持写入 Windows 用户环境变量。");
  }
  execFileSync("reg.exe", ["add", "HKCU\\Environment", "/v", name, "/t", "REG_SZ", "/d", value, "/f"], {
    stdio: ["ignore", "ignore", "pipe"],
    windowsHide: true
  });
  process.env[name] = value;
}

function defaultToolsText(tools) {
  return `生成 ${tools || "auto"} 工具集的常用命令菜单，包含基础查看、排查、补全示例和风险提醒。`;
}

function filterCommandEntries({ query = "", tool = "" } = {}) {
  const q = String(query || "").trim().toLowerCase();
  const selectedTool = String(tool || "").trim().toLowerCase();
  return commandCacheEntries().filter((entry) => {
    if (selectedTool && String(entry.tool || "").toLowerCase() !== selectedTool) return false;
    if (!q) return true;
    const haystack = [
      entry.tool,
      entry.command,
      entry.summary,
      ...(entry.aliases || []),
      ...(entry.tags || [])
    ].join(" ").toLowerCase();
    return haystack.includes(q);
  });
}

async function fetchDocumentText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const content = await response.text();
    return content
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .slice(0, 80000);
  } finally {
    clearTimeout(timer);
  }
}

async function handleCommands({ asJson, config }) {
  const sub = args.shift() || "list";
  const query = takeOption("--query", "");
  const tool = takeOption("--tool", "");

  if (sub === "list") {
    const commands = filterCommandEntries({ query, tool });
    if (asJson) {
      console.log(JSON.stringify({ userCachePath: userCommandCachePath(), commands }, null, 2));
      return;
    }
    for (const entry of commands) {
      console.log(`${entry.command}\t${entry.summary}`);
    }
    return;
  }

  if (sub === "add") {
    const command = takeOption("--command", "");
    const summary = takeOption("--summary", "");
    const tags = takeOption("--tags", "");
    const source = takeOption("--source", "user");
    const sourceUrl = takeOption("--url", "");
    const entry = addUserCommand({ tool: tool || "custom", command, summary, tags, source, sourceUrl });
    console.log(asJson ? JSON.stringify({ ok: true, userCachePath: userCommandCachePath(), entry }, null, 2) : `已新增：${entry.command}`);
    return;
  }

  if (sub === "delete" || sub === "remove") {
    const command = takeOption("--command", args.join(" ").trim());
    const result = deleteUserCommand(command);
    console.log(asJson ? JSON.stringify({ ok: true, ...result }, null, 2) : `已删除 ${result.deleted} 条`);
    return;
  }

  if (sub === "import") {
    const file = takeOption("--from-file", "");
    const url = takeOption("--url", "");
    const dryRun = takeFlag("--dry-run");
    const pieces = [];
    if (file) pieces.push(fs.readFileSync(file, "utf8"));
    if (url) pieces.push(await fetchDocumentText(url));
    const stdin = await readStdinIfPiped();
    if (stdin) pieces.push(stdin);
    const text = pieces.join("\n\n").trim();
    if (!text) {
      console.error("No document text provided. Use --from-file, --url, or pipe text.");
      process.exitCode = 2;
      return;
    }
    const commands = await requestCommandExtraction(config, { text, url, tool: tool || "custom" });
    if (dryRun) {
      console.log(asJson ? JSON.stringify({ commands }, null, 2) : commands.map((entry) => `${entry.command}\t${entry.summary}`).join("\n"));
      return;
    }
    const result = importUserCommands(commands);
    console.log(asJson ? JSON.stringify({ ok: true, userCachePath: userCommandCachePath(), ...result }, null, 2) : `已导入 ${result.imported} 条命令`);
    return;
  }

  console.error("用法: taih commands list|add|delete|import");
  process.exitCode = 2;
}

async function main() {
  const asJson = takeFlag("--json");
  const asRaw = takeFlag("--raw");
  const noCache = takeFlag("--no-cache");
  const stream = takeFlag("--stream");
  const replaceExisting = takeFlag("--replace") || takeFlag("--restart");
  const copyOutput = takeFlag("--copy");
  const outputStyle = takeOption("--style", process.env.TAIH_OUTPUT_STYLE || "standard");
  const tools = takeOption("--tools", process.env.TAIH_TOOLS || "auto");
  const instructionsFile = takeOption("--instructions-file", "");
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
    const { startServer } = await import("../../src/server/http-server.js");
    await startServer({ config, port, replaceExisting });
    return;
  }

  if (mode === "commands") {
    await handleCommands({ asJson, config });
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
      console.log("缓存已清理。");
      return;
    }
    if (sub === "stats") {
      const stats = cacheStats();
      if (asJson) {
        console.log(JSON.stringify(stats, null, 2));
      } else {
        console.log("terminal-ai-helper cache stats");
        console.log(`  cacheFiles: ${stats.files}/${stats.maxFiles}`);
        console.log(`  cacheSize:  ${(stats.bytes / 1024 / 1024).toFixed(2)} MB / ${(stats.maxBytes / 1024 / 1024).toFixed(0)} MB`);
        console.log(`  maxAge:     ${(stats.maxAgeMs / 24 / 60 / 60 / 1000).toFixed(0)} days`);
        console.log(`  history:    ${stats.historyLines}/${stats.maxHistoryLines} lines`);
      }
      return;
    }
    console.error("用法: taih cache clear | taih cache stats");
    process.exitCode = 2;
    return;
  }

  if (mode === "config") {
    const sub = args.shift() || "get";
    if (sub === "get") {
      console.log("terminal-ai-helper config");
      console.log(`  baseUrl: ${config.baseUrl}`);
      console.log(`  model: ${config.model}`);
      console.log(`  timeoutMs: ${config.timeoutMs}`);
      console.log(`  tools: ${process.env.TAIH_TOOLS || "auto"}`);
      console.log(`  authSource: ${config.authSource}`);
      return;
    }
    if (sub === "set") {
      const key = args.shift();
      const value = args.join(" ").trim();
      const map = {
        model: "TAIH_MODEL",
        "base-url": "TAIH_BASE_URL",
        timeout: "TAIH_TIMEOUT_MS",
        tools: "TAIH_TOOLS",
        proxy: "TAIH_PROXY"
      };
      const envName = map[key];
      if (!envName || !value) {
        console.error("用法: taih config set model <模型名> | base-url <地址> | timeout <毫秒> | tools <工具集>");
        process.exitCode = 2;
        return;
      }
      setUserEnv(envName, value);
      console.log(`已写入用户环境变量 ${envName}=${value}`);
      console.log("当前终端如果已经打开很久，建议重新加载 profile 或重开终端。");
      return;
    }
    console.error("用法: taih config get | taih config set model <模型名>");
    process.exitCode = 2;
    return;
  }

  if (mode === "doctor") {
    console.log("terminal-ai-helper doctor");
    console.log(`  baseUrl: ${config.baseUrl}`);
    console.log(`  model: ${config.model}`);
    console.log(`  tools: ${tools}`);
    console.log(`  apiKey: ${config.apiKey ? "found" : "missing"}`);
    console.log(`  authSource: ${config.authSource}`);
    console.log(`  proxy: ${config.proxyUrl ? "enabled" : "direct"}`);
    if (!config.apiKey) process.exitCode = 2;
    return;
  }

  if (!validModes.has(mode)) {
    console.error(`Unknown mode: ${mode}\n`);
    console.error(usage());
    process.exitCode = 2;
    return;
  }
  if (mode === "complete" && config.timeoutMs < 90000) {
    config.timeoutMs = 90000;
  }

  const stdin = await readStdinIfPiped();
  let source = stdin ? "stdin" : "arguments";
  let text = [...args, stdin].filter(Boolean).join(" ").trim();
  if (!text && fromClipboard) {
    text = readClipboard();
    source = "clipboard";
  }
  if (!text && mode === "tools") {
    text = defaultToolsText(tools);
    source = "tools-menu";
  }

  if (!text) {
    console.error("No command text provided.");
    process.exitCode = 2;
    return;
  }

  const shell = process.env.TAIH_SHELL || process.env.ComSpec || "terminal";
  const extraInstructions = instructionsFile ? await readInstructions(instructionsFile) : (process.env.TAIH_EXTRA_INSTRUCTIONS || "");
  const localHelp = process.env.TAIH_DISABLE_LOCAL_HELP === "1" ? null : getLocalHelp({ mode, text, outputStyle, tools });
  if (localHelp && !asJson && !asRaw && !noCache) {
    const output = renderHuman(localHelp, { style: outputStyle });
    appendHistory({ mode, text, source, cacheHit: true, title: localHelp.title, summary: localHelp.summary, output });
    if (copyOutput) writeClipboard(output);
    console.log(output);
    return;
  }

  const cacheText = `${tools}\0${outputStyle}\0${extraInstructions}\0${text}`;
  if ((stream || String(outputStyle).toLowerCase() === "custom") && !asJson && !asRaw) {
    const cacheMode = `stream:${mode}:${outputStyle}`;
    const cached = noCache ? null : getCache(cacheMode, cacheText);
    if (cached?.text) {
      process.stdout.write(cached.text);
      if (!cached.text.endsWith("\n")) process.stdout.write("\n");
      appendHistory({ mode, text, source, cacheHit: true, title: "stream-cache", summary: "cached stream output", output: cached.text });
      return;
    }
    const prompt = buildPlainPrompt({ mode, text, source, shell, outputStyle, extraInstructions, tools });
    const started = Date.now();
    const full = await requestCommandHelpTextStream(config, prompt, (chunk) => process.stdout.write(chunk));
    if (!full.endsWith("\n")) process.stdout.write("\n");
    if (!noCache && full.trim()) setCache(cacheMode, cacheText, { text: full });
    appendHistory({ mode, text, source, cacheHit: false, title: "stream", summary: `streamed in ${((Date.now() - started) / 1000).toFixed(1)}s`, output: full });
    return;
  }

  const prompt = buildPrompt({ mode, text, source, shell, outputStyle, extraInstructions, tools });
  let result = noCache ? null : getCache(mode, cacheText);
  const cacheHit = Boolean(result);
  if (!result) {
    result = await requestCommandHelp(config, prompt);
    setCache(mode, cacheText, result);
  }
  appendHistory({ mode, text, source, cacheHit, title: result.title, summary: result.summary });

  const output = asRaw ? renderRaw(result) : asJson ? renderJson(result) : renderHuman(result, { style: outputStyle });
  if (copyOutput) writeClipboard(output);
  console.log(output);
}

main().catch((error) => {
  console.error(`terminal-ai-helper failed: ${error.message}`);
  if (process.env.TAIH_DEBUG) console.error(error.stack);
  process.exitCode = 1;
});
