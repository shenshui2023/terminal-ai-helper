const labels = {
  confidence: "\u53ef\u4fe1\u5ea6",
  completion: "\u5efa\u8bae\u8865\u5168",
  usage: "\u5e38\u89c4\u7528\u6cd5",
  examples: "\u793a\u4f8b",
  purpose: "\u4f5c\u7528",
  risks: "\u98ce\u9669\u63d0\u9192",
  nextSteps: "\u4e0b\u4e00\u6b65"
};

export function renderJson(result) {
  return JSON.stringify(result, null, 2);
}

export function renderRaw(result) {
  return result.completion || "";
}

function section(title, items) {
  if (!items.length) return "";
  return [`\n${title}:`, ...items.map((item) => `  - ${item}`)].join("\n");
}

function exampleSection(items) {
  if (!items.length) return "";
  const lines = [`\n${labels.examples}:`];
  for (const item of items) {
    if (typeof item === "string") {
      lines.push(`  - ${item}`);
      continue;
    }
    lines.push(`  - ${item.command}`);
    if (item.purpose) lines.push(`    ${labels.purpose}: ${item.purpose}`);
  }
  return lines.join("\n");
}

export function renderHuman(result) {
  const lines = [];
  lines.push(`\n${result.title}`);
  if (result.summary) lines.push(result.summary);
  lines.push(`${labels.confidence}: ${result.confidence}`);
  if (result.completion) lines.push(`\n${labels.completion}: ${result.completion}`);
  lines.push(section(labels.usage, result.usage));
  lines.push(exampleSection(result.examples));
  lines.push(section(labels.risks, result.risks));
  lines.push(section(labels.nextSteps, result.next_steps));
  return lines.filter(Boolean).join("\n");
}
