const zh = {
  user: "用户名",
  host: "主机",
  port: "端口",
  filePath: "文件路径",
  service: "服务名",
  process: "进程名",
  package: "包名",
  device: "设备序列号"
};

const placeholders = [
  `<${zh.user}>`,
  `<${zh.host}>`,
  `<${zh.port}>`,
  `<${zh.filePath}>`,
  `<${zh.service}>`,
  `<${zh.process}>`,
  `<${zh.package}>`,
  `<${zh.device}>`
].join(", ");

const schemaInstruction = `Return only compact JSON with this shape:
{
  "title": "short Chinese title",
  "summary": "one sentence",
  "confidence": "high|medium|low",
  "completion": "exact text to append, or empty string",
  "usage": ["clear usage point"],
  "examples": [
    {
      "command": "copyable command using placeholders like ${placeholders}",
      "purpose": "what this command does"
    }
  ],
  "risks": ["risk or safety note"],
  "next_steps": ["actionable next step"]
}`;

function styleInstructions(outputStyle = "standard", extraInstructions = "") {
  const style = String(outputStyle || "standard").toLowerCase();
  const rules = {
    brief: [
      "Output must be short: at most 8 lines.",
      "Use this order: purpose, common usage, at most 2 examples, risks if any.",
      "Separate sections with one blank line.",
      "Use two-space indentation for bullets and example purposes.",
      "Do not include long tables, exhaustive parameter lists, or background essays."
    ],
    standard: [
      "Output should be practical and not verbose.",
      "Prefer bullets over long paragraphs.",
      "Separate sections with one blank line and keep indentation readable.",
      "Include examples only when they clarify real usage."
    ],
    examples: [
      "Focus on copyable examples.",
      "Use placeholders for variable parts.",
      "Explain each example in one short sentence.",
      "Put a blank line between examples when the answer is longer than four lines."
    ],
    custom: [
      "Follow the user's custom output rules exactly when they are safe.",
      "If the answer would violate the custom rules, rewrite it until it matches the rules.",
      "Keep blank lines and indentation readable unless the custom rules explicitly say otherwise."
    ]
  }[style] || [];

  const custom = String(extraInstructions || "").trim();
  if (custom) {
    rules.push("Custom output rules:");
    rules.push(custom);
  }
  return rules;
}

export function buildPrompt({ mode, text, shell, source = "typed text", outputStyle = "standard", extraInstructions = "" }) {
  const task = {
    explain: "Explain this terminal command. Include common usage, parameters, examples, and risks.",
    complete: "Complete the current terminal command prefix. Prefer a safe, conventional continuation. The completion field must contain only text to append after the prefix.",
    fix: "Diagnose this terminal error or failed command. Explain the likely cause and provide a fix."
  }[mode];

  return {
    system: [
      "You are a senior terminal assistant for Windows PowerShell, CMD, Git, SSH, Python, Java, Node.js, Docker, Android/ADB, and embedded development.",
      "Answer in Simplified Chinese.",
      "Be concise, practical, and safe.",
      "Never suggest destructive commands unless the user explicitly asks; if a command can delete data, say so clearly.",
      "When completing, preserve the user's intent and avoid inventing private paths or secrets.",
      `For examples, use angle-bracket placeholders for variable parts, such as ${placeholders}.`,
      "Do not replace placeholders with fake real values unless the user already provided the value.",
      "Every example must explain the command's purpose in the purpose field.",
      "If the input came from a selected fragment, explain that fragment as the active context.",
      ...styleInstructions(outputStyle, extraInstructions),
      schemaInstruction
    ].join("\n"),
    user: [
      `Mode: ${mode}`,
      `Shell/context: ${shell}`,
      `Input source: ${source}`,
      `Task: ${task}`,
      "Input:",
      text
    ].join("\n")
  };
}

export function buildPlainPrompt({ mode, text, shell, source = "typed text", outputStyle = "standard", extraInstructions = "" }) {
  const task = {
    explain: "解释这条终端命令的作用、常规用法、参数、示例和风险。",
    complete: "补全当前终端命令。先给出建议补全文本，再简短说明原因。",
    fix: "诊断这条命令或报错的原因，并给出明确修复步骤。"
  }[mode];

  return {
    system: [
      "你是资深终端命令助手，熟悉 PowerShell、CMD、Linux shell、Git、SSH、Python、Java、Node.js、Docker、ADB 和嵌入式开发。",
      "用简体中文回答。",
      "输出要清晰、可扫描、实用。",
      `示例中的可变内容必须用尖括号占位，例如 ${placeholders}。`,
      "每条示例都要说明作用。",
      "如果命令有删除、覆盖、停止服务等风险，必须明确提醒。",
      ...styleInstructions(outputStyle, extraInstructions)
    ].join("\n"),
    user: [
      `模式: ${mode}`,
      `Shell/context: ${shell}`,
      `输入来源: ${source}`,
      `任务: ${task}`,
      "输入:",
      text
    ].join("\n")
  };
}
