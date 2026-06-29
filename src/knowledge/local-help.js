import { helpForCommand, toolMenu } from "./command-cache.js";

function firstCommand(text) {
  return String(text || "").trim().split(/\s+/)[0]?.toLowerCase();
}

function shouldUseBriefCache({ outputStyle, mode }) {
  if (mode === "tools") return true;
  return String(outputStyle || "").toLowerCase() === "brief";
}

export function getLocalHelp({ mode, text, outputStyle, tools }) {
  if (!shouldUseBriefCache({ outputStyle, mode })) return null;

  if (mode === "tools") {
    return toolMenu({ tools });
  }

  if (mode === "complete") {
    return helpForCommand(text, { tools, limit: 10 });
  }

  if (mode !== "explain") return null;

  const command = firstCommand(text);
  if (!command) return null;
  return helpForCommand(text, { tools, limit: 10 });
}
