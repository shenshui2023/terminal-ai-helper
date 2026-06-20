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

export function renderHuman(result, options = {}) {
  const style = String(options.style || "standard").toLowerCase();
  const usage = style === "brief" ? result.usage.slice(0, 2) : result.usage;
  const examples = style === "brief" ? result.examples.slice(0, 2) : result.examples;
  const risks = style === "brief" ? result.risks.slice(0, 1) : result.risks;
  const nextSteps = style === "brief" ? result.next_steps.slice(0, 1) : result.next_steps;
  const lines = [];
  lines.push(`\n${result.title}`);
  if (result.summary) lines.push(result.summary);
  if (style !== "brief") lines.push(`${labels.confidence}: ${result.confidence}`);
  if (result.completion) lines.push(`\n${labels.completion}: ${result.completion}`);
  lines.push(section(labels.usage, usage));
  lines.push(exampleSection(examples));
  lines.push(section(labels.risks, risks));
  lines.push(section(labels.nextSteps, nextSteps));
  return lines.filter(Boolean).join("\n");
}
