#!/usr/bin/env node
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { loadConfig } from "../src/config.js";
import { requestCommandHelp, requestCommandHelpTextStream } from "../src/api.js";
import { buildPlainPrompt, buildPrompt } from "../src/prompts.js";
import { renderHuman, renderJson, renderRaw } from "../src/render.js";
import { readClipboard, writeClipboard } from "../src/clipboard.js";
import { appendHistory, cacheStats, clearCache, getCache, readHistory, setCache } from "../src/store.js";
import { getLocalHelp } from "../src/local-help.js";

const args = process.argv.slice(2);

function usage() {
  return `用法:
  taih explain <命令...>             解释命令用法、风险和示例
  taih complete [--json] <前缀...>   根据当前输入补全命令
  taih fix [--json] <报错...>        诊断报错并给出修复建议
  taih clipboard [模式]              读取剪贴板并执行 explain/complete/fix
  taih serve [--port 17888]          启动本地 HTTP helper，供 SSH 反向隧道使用
  taih history [--json]              查看最近的命令帮助历史
  taih cache clear                   清理本地缓存
  taih cache stats                   查看缓存和历史占用
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
  --instructions-file <文件>          追加自定义输出规则或提示词

环境变量:
  TAIH_BASE_URL        API 地址，默认 https://qyapi.cjyyswq.com
  TAIH_MODEL           模型名，默认 gpt-5.5
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
    throw new Error("config set currently supports Windows user environment variables only.");
  }
  execFileSync("reg.exe", ["add", "HKCU\\Environment", "/v", name, "/t", "REG_SZ", "/d", value, "/f"], {
    stdio: ["ignore", "ignore", "pipe"],
    windowsHide: true
  });
  process.env[name] = value;
}

async function main() {
  const asJson = takeFlag("--json");
  const asRaw = takeFlag("--raw");
  const noCache = takeFlag("--no-cache");
  const stream = takeFlag("--stream");
  const copyOutput = takeFlag("--copy");
  const outputStyle = takeOption("--style", process.env.TAIH_OUTPUT_STYLE || "standard");
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
      console.log(`  authSource: ${config.authSource}`);
      return;
    }
    if (sub === "set") {
      const key = args.shift();
      const value = args.join(" ").trim();
      const map = {
        model: "TAIH_MODEL",
        "base-url": "TAIH_BASE_URL",
        timeout: "TAIH_TIMEOUT_MS"
      };
      const envName = map[key];
      if (!envName || !value) {
        console.error("用法: taih config set model <模型名> | base-url <地址> | timeout <毫秒>");
        process.exitCode = 2;
        return;
      }
      setUserEnv(envName, value);
      console.log(`已写入用户环境变量 ${envName}=${value}`);
      console.log("当前终端如已打开很久，建议重新加载 profile 或重开终端。");
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
  const extraInstructions = instructionsFile ? await readInstructions(instructionsFile) : (process.env.TAIH_EXTRA_INSTRUCTIONS || "");
  const localHelp = process.env.TAIH_DISABLE_LOCAL_HELP === "1" ? null : getLocalHelp({ mode, text, outputStyle });
  if (localHelp && !asJson && !asRaw && !noCache) {
    const output = renderHuman(localHelp, { style: outputStyle });
    appendHistory({ mode, text, source, cacheHit: true, title: localHelp.title, summary: localHelp.summary, output });
    if (copyOutput) writeClipboard(output);
    console.log(output);
    return;
  }

  if ((stream || String(outputStyle).toLowerCase() === "custom") && !asJson && !asRaw) {
    const cacheMode = `stream:${mode}:${outputStyle}`;
    const cacheText = `${text}\0${extraInstructions}`;
    const cached = noCache ? null : getCache(cacheMode, cacheText);
    if (cached?.text) {
      process.stdout.write(cached.text);
      if (!cached.text.endsWith("\n")) process.stdout.write("\n");
      appendHistory({ mode, text, source, cacheHit: true, title: "stream-cache", summary: "cached stream output", output: cached.text });
      return;
    }
    const prompt = buildPlainPrompt({ mode, text, source, shell, outputStyle, extraInstructions });
    const started = Date.now();
    let full = "";
    full = await requestCommandHelpTextStream(config, prompt, (chunk) => process.stdout.write(chunk));
    if (!full.endsWith("\n")) process.stdout.write("\n");
    if (!noCache && full.trim()) setCache(cacheMode, cacheText, { text: full });
    appendHistory({ mode, text, source, cacheHit: false, title: "stream", summary: `streamed in ${((Date.now() - started) / 1000).toFixed(1)}s`, output: full });
    return;
  }

  const prompt = buildPrompt({ mode, text, source, shell, outputStyle, extraInstructions });
  let result = noCache ? null : getCache(mode, text);
  const cacheHit = Boolean(result);
  if (!result) {
    result = await requestCommandHelp(config, prompt);
    setCache(mode, text, result);
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
