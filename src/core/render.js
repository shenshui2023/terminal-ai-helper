const labels = {
  confidence: "\u53ef\u4fe1\u5ea6",
  completion: "\u5efa\u8bae\u8865\u5168",
  usage: "\u5e38\u89c4\u7528\u6cd5",
  examples: "\u793a\u4f8b",
  related: "\u76f8\u5173\u547d\u4ee4",
  when: "\u9002\u7528\u573a\u666f",
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

function commandSection(title, items) {
  if (!items.length) return "";
  const lines = [`\n${title}:`];
  for (const item of items) {
    if (typeof item === "string") {
      lines.push(`  - ${item}`);
      lines.push("");
      continue;
    }
    lines.push(`  - ${item.command}`);
    if (item.purpose) lines.push(`    ${labels.purpose}: ${item.purpose}`);
    if (item.when) lines.push(`    ${labels.when}: ${item.when}`);
    lines.push("");
  }
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  return lines.join("\n");
}

export function renderHuman(result, options = {}) {
  const style = String(options.style || "standard").toLowerCase();
  const usage = style === "brief" ? result.usage.slice(0, 4) : result.usage;
  const related = style === "brief" ? (result.related_commands || []).slice(0, 4) : (result.related_commands || []);
  const examples = style === "brief" ? result.examples.slice(0, 3) : result.examples;
  const risks = style === "brief" ? result.risks.slice(0, 1) : result.risks;
  const nextSteps = style === "brief" ? result.next_steps.slice(0, 1) : result.next_steps;
  const lines = [];
  lines.push(`\n${result.title}`);
  if (result.summary) lines.push(result.summary);
  if (style !== "brief") lines.push(`${labels.confidence}: ${result.confidence}`);
  if (result.completion) lines.push(`\n${labels.completion}: ${result.completion}`);
  lines.push(section(labels.usage, usage));
  lines.push(commandSection(labels.related, related));
  lines.push(commandSection(labels.examples, examples));
  lines.push(section(labels.risks, risks));
  lines.push(section(labels.nextSteps, nextSteps));
  return lines.filter(Boolean).join("\n");
}
