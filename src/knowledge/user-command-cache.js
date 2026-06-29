import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const defaultCachePath = path.join(os.homedir(), ".terminal-ai-helper", "command-cache.user.json");

export function userCommandCachePath() {
  return process.env.TAIH_USER_COMMAND_CACHE || defaultCachePath;
}

export function readUserCommandCache() {
  const file = userCommandCachePath();
  try {
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    return {
      version: Number(parsed.version || 1),
      commands: Array.isArray(parsed.commands) ? parsed.commands.map(normalizeCommandEntry).filter(Boolean) : []
    };
  } catch (error) {
    if (error.code === "ENOENT") return { version: 1, commands: [] };
    return { version: 1, commands: [] };
  }
}

export function writeUserCommandCache(data) {
  const file = userCommandCachePath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const commands = Array.isArray(data?.commands)
    ? data.commands.map(normalizeCommandEntry).filter(Boolean)
    : [];
  fs.writeFileSync(file, `${JSON.stringify({ version: 1, commands }, null, 2)}\n`, "utf8");
  return { version: 1, commands };
}

export function normalizeCommandEntry(entry) {
  if (!entry || typeof entry !== "object") return null;
  const command = textOf(entry.command);
  const summary = textOf(entry.summary);
  if (!command || !summary) return null;
  return {
    tool: textOf(entry.tool) || "custom",
    command,
    summary,
    aliases: listOf(entry.aliases),
    tags: listOf(entry.tags),
    source: textOf(entry.source) || "user",
    sourceUrl: textOf(entry.sourceUrl || entry.url)
  };
}

export function addUserCommand(entry) {
  const normalized = normalizeCommandEntry(entry);
  if (!normalized) {
    throw new Error("Command and summary are required.");
  }
  const cache = readUserCommandCache();
  const key = keyOf(normalized.command);
  const commands = cache.commands.filter((item) => keyOf(item.command) !== key);
  commands.unshift(normalized);
  writeUserCommandCache({ commands });
  return normalized;
}

export function deleteUserCommand(command) {
  const key = keyOf(command);
  if (!key) return { deleted: 0 };
  const cache = readUserCommandCache();
  const commands = cache.commands.filter((item) => keyOf(item.command) !== key);
  writeUserCommandCache({ commands });
  return { deleted: cache.commands.length - commands.length };
}

export function importUserCommands(entries) {
  const incoming = Array.isArray(entries)
    ? entries.map(normalizeCommandEntry).filter(Boolean)
    : [];
  const cache = readUserCommandCache();
  const byKey = new Map();
  for (const entry of cache.commands) byKey.set(keyOf(entry.command), entry);
  for (const entry of incoming) byKey.set(keyOf(entry.command), entry);
  const commands = [...incoming, ...cache.commands]
    .map((entry) => byKey.get(keyOf(entry.command)))
    .filter(uniqueByCommand());
  writeUserCommandCache({ commands });
  return { imported: incoming.length, commands: incoming };
}

function uniqueByCommand() {
  const seen = new Set();
  return (entry) => {
    const key = keyOf(entry.command);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  };
}

function keyOf(value) {
  return textOf(value).toLowerCase().replace(/\s+/g, " ");
}

function textOf(value) {
  return String(value || "").trim();
}

function listOf(value) {
  if (Array.isArray(value)) return value.map(textOf).filter(Boolean);
  if (typeof value === "string") return value.split(/[,;\n]+/).map(textOf).filter(Boolean);
  return [];
}
