export function renderJson(result) {
  return JSON.stringify(result, null, 2);
}

function section(title, items) {
  if (!items.length) return "";
  return [`\n${title}:`, ...items.map((item) => `  - ${item}`)].join("\n");
}

function exampleSection(items) {
  if (!items.length) return "";
  const lines = ["\n示例:"];
  for (const item of items) {
    if (typeof item === "string") {
      lines.push(`  - ${item}`);
      continue;
    }
    lines.push(`  - ${item.command}`);
    if (item.purpose) lines.push(`    作用: ${item.purpose}`);
  }
  return lines.join("\n");
}

export function renderHuman(result) {
  const lines = [];
  lines.push(`\n${result.title}`);
  if (result.summary) lines.push(result.summary);
  lines.push(`可信度: ${result.confidence}`);
  if (result.completion) lines.push(`\n建议补全: ${result.completion}`);
  lines.push(section("常规用法", result.usage));
  lines.push(exampleSection(result.examples));
  lines.push(section("风险提醒", result.risks));
  lines.push(section("下一步", result.next_steps));
  return lines.filter(Boolean).join("\n");
}
