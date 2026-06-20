import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const appDir = path.join(os.homedir(), ".terminal-ai-helper");
const cacheDir = path.join(appDir, "cache");
const historyFile = path.join(appDir, "history.jsonl");
const maxHistoryLines = Number(process.env.TAIH_MAX_HISTORY_LINES || 300);
const maxCacheFiles = Number(process.env.TAIH_MAX_CACHE_FILES || 500);
const maxCacheBytes = Number(process.env.TAIH_MAX_CACHE_BYTES || 50 * 1024 * 1024);
const defaultCacheMaxAgeMs = Number(process.env.TAIH_CACHE_MAX_AGE_MS || 7 * 24 * 60 * 60 * 1000);

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function keyFor(mode, text) {
  return crypto.createHash("sha256").update(`${mode}\0${text}`).digest("hex");
}

export function getCache(mode, text, maxAgeMs = defaultCacheMaxAgeMs) {
  try {
    const file = path.join(cacheDir, `${keyFor(mode, text)}.json`);
    const stat = fs.statSync(file);
    if (Date.now() - stat.mtimeMs > maxAgeMs) {
      fs.rmSync(file, { force: true });
      return null;
    }
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

export function setCache(mode, text, value) {
  ensureDir(cacheDir);
  const file = path.join(cacheDir, `${keyFor(mode, text)}.json`);
  fs.writeFileSync(file, JSON.stringify(value), "utf8");
  pruneCache();
}

export function clearCache() {
  fs.rmSync(cacheDir, { recursive: true, force: true });
}

export function appendHistory(entry) {
  ensureDir(appDir);
  fs.appendFileSync(historyFile, `${JSON.stringify({ ...entry, at: new Date().toISOString() })}\n`, "utf8");
  pruneHistory();
}

export function readHistory(limit = 30) {
  try {
    const lines = fs.readFileSync(historyFile, "utf8").trim().split(/\r?\n/).filter(Boolean);
    return lines.slice(-limit).map((line) => JSON.parse(line)).reverse();
  } catch {
    return [];
  }
}

function listCacheFiles() {
  try {
    return fs.readdirSync(cacheDir)
      .filter((name) => name.endsWith(".json"))
      .map((name) => {
        const file = path.join(cacheDir, name);
        const stat = fs.statSync(file);
        return { file, size: stat.size, mtimeMs: stat.mtimeMs };
      })
      .sort((a, b) => a.mtimeMs - b.mtimeMs);
  } catch {
    return [];
  }
}

function pruneCache() {
  const now = Date.now();
  let files = listCacheFiles();
  for (const item of files) {
    if (now - item.mtimeMs > defaultCacheMaxAgeMs) {
      fs.rmSync(item.file, { force: true });
    }
  }

  files = listCacheFiles();
  let total = files.reduce((sum, item) => sum + item.size, 0);
  while (files.length > maxCacheFiles || total > maxCacheBytes) {
    const oldest = files.shift();
    if (!oldest) break;
    fs.rmSync(oldest.file, { force: true });
    total -= oldest.size;
  }
}

function pruneHistory() {
  if (!Number.isFinite(maxHistoryLines) || maxHistoryLines <= 0) return;
  try {
    const lines = fs.readFileSync(historyFile, "utf8").split(/\r?\n/).filter(Boolean);
    if (lines.length <= maxHistoryLines) return;
    fs.writeFileSync(historyFile, `${lines.slice(-maxHistoryLines).join("\n")}\n`, "utf8");
  } catch {
    // Ignore history pruning failures; history is only a convenience feature.
  }
}

export function cacheStats() {
  const files = listCacheFiles();
  return {
    files: files.length,
    bytes: files.reduce((sum, item) => sum + item.size, 0),
    maxFiles: maxCacheFiles,
    maxBytes: maxCacheBytes,
    maxAgeMs: defaultCacheMaxAgeMs,
    historyLines: readHistory(maxHistoryLines + 1).length,
    maxHistoryLines
  };
}

export function paths() {
  return { appDir, cacheDir, historyFile };
}
