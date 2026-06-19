#!/usr/bin/env node
import { loadConfig } from "../src/config.js";
import { requestCommandHelp } from "../src/api.js";
import { buildPrompt } from "../src/prompts.js";
import { renderHuman, renderJson } from "../src/render.js";

const args = process.argv.slice(2);

function usage() {
  return `Usage:
  taih explain <command...>          Explain usage, risks, examples
  taih complete [--json] <prefix...> Suggest completions for current command
  taih fix [--json] <error...>       Explain an error and propose a fix
  taih doctor                        Check local configuration

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

async function readStdinIfPiped() {
  if (process.stdin.isTTY) return "";
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data.trim();
}

async function main() {
  const mode = args.shift();
  const asJson = takeFlag("--json");
  const separator = args.indexOf("--");
  if (separator !== -1) args.splice(separator, 1);
  const config = loadConfig();

  if (!mode || mode === "-h" || mode === "--help") {
    console.log(usage());
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
  const text = [...args, stdin].filter(Boolean).join(" ").trim();
  if (!text) {
    console.error("No command text provided.");
    process.exitCode = 2;
    return;
  }

  const prompt = buildPrompt({ mode, text, shell: process.env.TAIH_SHELL || process.env.ComSpec || "terminal" });
  const result = await requestCommandHelp(config, prompt);

  if (asJson) {
    console.log(renderJson(result));
  } else {
    console.log(renderHuman(result));
  }
}

main().catch((error) => {
  console.error(`terminal-ai-helper failed: ${error.message}`);
  if (process.env.TAIH_DEBUG) console.error(error.stack);
  process.exitCode = 1;
});
