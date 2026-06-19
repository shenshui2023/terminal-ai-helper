import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const appDir = path.join(os.homedir(), ".terminal-ai-helper");
const cacheDir = path.join(appDir, "cache");
const historyFile = path.join(appDir, "history.jsonl");

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function keyFor(mode, text) {
  return crypto.createHash("sha256").update(`${mode}\0${text}`).digest("hex");
}

export function getCache(mode, text, maxAgeMs = 7 * 24 * 60 * 60 * 1000) {
  try {
    const file = path.join(cacheDir, `${keyFor(mode, text)}.json`);
    const stat = fs.statSync(file);
    if (Date.now() - stat.mtimeMs > maxAgeMs) return null;
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

export function setCache(mode, text, value) {
  ensureDir(cacheDir);
  const file = path.join(cacheDir, `${keyFor(mode, text)}.json`);
  fs.writeFileSync(file, JSON.stringify(value), "utf8");
}

export function clearCache() {
  fs.rmSync(cacheDir, { recursive: true, force: true });
}

export function appendHistory(entry) {
  ensureDir(appDir);
  fs.appendFileSync(historyFile, `${JSON.stringify({ ...entry, at: new Date().toISOString() })}\n`, "utf8");
}

export function readHistory(limit = 30) {
  try {
    const lines = fs.readFileSync(historyFile, "utf8").trim().split(/\r?\n/).filter(Boolean);
    return lines.slice(-limit).map((line) => JSON.parse(line)).reverse();
  } catch {
    return [];
  }
}

export function paths() {
  return { appDir, cacheDir, historyFile };
}
