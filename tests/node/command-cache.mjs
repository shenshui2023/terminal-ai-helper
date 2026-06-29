import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "taih-command-cache-"));
process.env.TAIH_USER_COMMAND_CACHE = path.join(tempDir, "command-cache.user.json");

const cacheFile = path.resolve("src/knowledge/command-cache.json");
const cacheStat = fs.statSync(cacheFile);
assert.ok(cacheStat.size < 100 * 1024 * 1024, "built-in command cache must stay below 100MB");

const cache = await import("../../src/knowledge/command-cache.js");
const user = await import("../../src/knowledge/user-command-cache.js");

assert.ok(
  cache.completionCandidates("systemctl", { limit: 5 }).some((item) => item.includes("\t查看服务状态")),
  "systemctl candidates should include a Chinese usage summary"
);

assert.ok(
  cache.completionCandidates("Get-Service", { tools: "windows", limit: 5 }).some((item) => item.includes("查看 Windows 服务")),
  "Windows built-in commands should include Chinese summaries"
);

assert.ok(
  cache.completionCandidates("redis-cli", { tools: "redis", limit: 5 }).some((item) => item.includes("检查 Redis")),
  "Redis official commands should be available in the built-in cache"
);

assert.ok(
  cache.completionCandidates("CREATE TABLE", { tools: "mysql", limit: 8 }).some((item) => item.includes("创建表")),
  "MySQL SQL statement cache should include DDL statements from the official reference"
);

assert.ok(
  cache.completionCandidates("SHOW ENGINE INNODB STATUS", { tools: "mysql", limit: 8 }).some((item) => item.includes("InnoDB")),
  "MySQL SQL statement cache should include diagnostic SHOW statements"
);

const added = user.addUserCommand({
  tool: "custom",
  command: "demo-tool status <名称>",
  summary: "查看 demo 工具状态",
  tags: "demo,status"
});
assert.equal(added.command, "demo-tool status <名称>");
assert.ok(
  cache.completionCandidates("demo-tool", { limit: 5 }).some((item) => item.startsWith("demo-tool status")),
  "user command should be merged into completion candidates"
);

const deleted = user.deleteUserCommand("demo-tool status <名称>");
assert.equal(deleted.deleted, 1);
assert.equal(
  cache.completionCandidates("demo-tool", { limit: 5 }).some((item) => item.startsWith("demo-tool status")),
  false,
  "deleted user command should no longer be returned"
);

fs.rmSync(tempDir, { recursive: true, force: true });
