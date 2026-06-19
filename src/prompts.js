const zh = {
  user: "\u7528\u6237\u540d",
  host: "\u4e3b\u673a",
  port: "\u7aef\u53e3",
  filePath: "\u6587\u4ef6\u8def\u5f84",
  service: "\u670d\u52a1\u540d",
  process: "\u8fdb\u7a0b\u540d",
  package: "\u5305\u540d",
  device: "\u8bbe\u5907\u5e8f\u5217\u53f7"
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

export function buildPrompt({ mode, text, shell, source = "typed text" }) {
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

export function buildPlainPrompt({ mode, text, shell, source = "typed text" }) {
  const task = {
    explain: "解释这条终端命令的作用、常规用法、参数、示例和风险。",
    complete: "补全当前终端命令。先给出建议补全文本，再简短说明原因。",
    fix: "诊断这条命令或报错的原因，并给出明确修复步骤。"
  }[mode];

  return {
    system: [
      "你是资深终端命令助手，熟悉 PowerShell、CMD、Linux shell、Git、SSH、Python、Java、Node.js、Docker、ADB 和嵌入式开发。",
      "用简体中文回答。",
      "输出要清晰、可扫读、实用。",
      "示例中的可变内容必须用尖括号占位，例如 <用户名>、<主机>、<端口>、<文件路径>、<服务名>、<进程名>、<包名>。",
      "每条示例都要说明作用。",
      "如果命令有删除、覆盖、停止服务等风险，必须明确提醒。"
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
