import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readUserCommandCache } from "./user-command-cache.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const builtinCachePath = path.join(__dirname, "command-cache.json");
const builtinCacheStat = fs.statSync(builtinCachePath);
if (builtinCacheStat.size > 100 * 1024 * 1024) {
  throw new Error("Command cache is larger than 100MB. Please split or clean it before loading.");
}
const data = JSON.parse(fs.readFileSync(builtinCachePath, "utf8"));

function textOf(value) {
  return String(value || "").trim();
}

function normalizeCommandName(value) {
  const text = textOf(value).toLowerCase();
  if (text === "kube") return "kubectl";
  if (text === "system") return "systemctl";
  return text;
}

function normalizePrefix(value) {
  const text = textOf(value);
  if (!text) return "";
  if (/^kube(\s|$)/i.test(text)) return text.replace(/^kube/i, "kubectl");
  if (/^system(\s|$)/i.test(text)) return text.replace(/^system/i, "systemctl");
  return text;
}

function commandTokens(value) {
  return textOf(value).toLowerCase().split(/\s+/).filter(Boolean);
}

function scoreEntry(entry, prefix, tools = "") {
  const normalizedPrefix = normalizePrefix(prefix).toLowerCase();
  const command = entry.command.toLowerCase();
  const aliases = (entry.aliases || []).map((item) => item.toLowerCase());
  const haystack = [command, ...aliases, entry.summary, entry.tool, ...(entry.tags || [])].join(" ").toLowerCase();
  const selectedTools = String(tools || "").toLowerCase().split(/[,;\s]+/).filter(Boolean);
  let score = 0;

  if (!normalizedPrefix) score += 1;
  if (command.startsWith(normalizedPrefix)) score += 100;
  if (aliases.some((item) => item.startsWith(normalizedPrefix))) score += 95;
  if (haystack.includes(normalizedPrefix)) score += 40;

  const tokens = commandTokens(normalizedPrefix);
  for (const token of tokens) {
    if (haystack.includes(token)) score += 10;
  }

  if (selectedTools.includes(entry.tool) || selectedTools.some((tool) => (entry.tags || []).includes(tool))) {
    score += 8;
  }

  const first = normalizeCommandName(tokens[0] || "");
  if (first && (entry.command.toLowerCase().startsWith(first) || entry.tool === first || (entry.tags || []).includes(first))) {
    score += 25;
  }

  return score;
}

export function commandCacheSources() {
  return [
    ...(data.sources || []),
    {
      id: "user",
      name: "用户自定义命令缓存",
      url: "local:user-command-cache"
    }
  ];
}

export function commandCacheEntries() {
  const userCommands = readUserCommandCache().commands || [];
  return uniqueEntries([...userCommands, ...(data.commands || [])]);
}

function uniqueEntries(entries) {
  const seen = new Set();
  const result = [];
  for (const entry of entries) {
    const key = String(entry?.command || "").trim().toLowerCase().replace(/\s+/g, " ");
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(entry);
  }
  return result;
}

export function findCommandEntries(prefix, { tools = "auto", limit = 12 } = {}) {
  const scored = commandCacheEntries()
    .map((entry, index) => ({ entry, index, score: scoreEntry(entry, prefix, tools) }))
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score || a.index - b.index);
  return scored.slice(0, limit).map((item) => item.entry);
}

export function formatCandidate(entry) {
  return `${entry.command}\t${entry.summary}`;
}

export function completionCandidates(prefix, options = {}) {
  return findCommandEntries(prefix, options).map(formatCandidate);
}

export function helpForCommand(text, { tools = "auto", limit = 8 } = {}) {
  const entries = findCommandEntries(text, { tools, limit });
  if (!entries.length) return null;
  const first = entries[0];
  return {
    title: `${first.command.split(/\s+/)[0]} 常用说明`,
    summary: first.summary,
    confidence: "high",
    completion: first.command,
    completions: entries.slice(0, 8).map((entry) => entry.command),
    usage: entries.slice(0, 5).map((entry) => `\`${entry.command}\` ${entry.summary}`),
    examples: entries.slice(0, 4).map((entry) => ({
      command: entry.command,
      purpose: entry.summary
    })),
    related_commands: entries.slice(1, 9).map((entry) => ({
      command: entry.command,
      purpose: entry.summary,
      when: `需要 ${entry.tags?.slice(0, 2).join(" / ") || entry.tool} 相关操作时`
    })),
    risks: [],
    next_steps: []
  };
}

export function toolMenu({ tools = "auto", limitPerTool = 6 } = {}) {
  const selected = String(tools || "auto").toLowerCase().split(/[,;\s]+/).filter((item) => item && item !== "auto");
  const groups = new Map();
  for (const entry of commandCacheEntries()) {
    if (selected.length && !selected.includes(entry.tool) && !selected.some((tool) => (entry.tags || []).includes(tool))) continue;
    if (!groups.has(entry.tool)) groups.set(entry.tool, []);
    const items = groups.get(entry.tool);
    if (items.length < limitPerTool) items.push(entry);
  }
  const entries = [...groups.entries()].flatMap(([, items]) => items);
  return {
    title: "常用命令一级缓存",
    summary: "这些命令来自官方文档整理，适合在补全和工具菜单里直接快速展示。",
    confidence: "high",
    completion: "",
    completions: entries.slice(0, 12).map((entry) => entry.command),
    usage: entries.slice(0, 18).map((entry) => `\`${entry.command}\` ${entry.summary}`),
    examples: entries.slice(0, 8).map((entry) => ({ command: entry.command, purpose: entry.summary })),
    related_commands: entries.slice(8, 24).map((entry) => ({
      command: entry.command,
      purpose: entry.summary,
      when: `${entry.tool} 常规操作`
    })),
    risks: ["delete、down、stop、restart、rm 这类命令会改变服务或数据状态，执行前确认目标。"],
    next_steps: ["在补全框里输入工具名前缀，例如 kubectl、docker、mysql、systemctl，即可优先显示本地缓存候选。"]
  };
}
