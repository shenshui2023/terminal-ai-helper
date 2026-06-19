const schemaInstruction = `Return only compact JSON with this shape:
{
  "title": "short Chinese title",
  "summary": "one sentence",
  "confidence": "high|medium|low",
  "completion": "exact text to append, or empty string",
  "usage": ["clear usage point"],
  "examples": [
    {
      "command": "copyable command using placeholders like <用户名>, <主机>, <端口>, <文件路径>",
      "purpose": "what this command does"
    }
  ],
  "risks": ["risk or safety note"],
  "next_steps": ["actionable next step"]
}`;

export function buildPrompt({ mode, text, shell }) {
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
      "For examples, use angle-bracket placeholders for variable parts, such as <用户名>, <主机>, <端口>, <文件路径>, <服务名>, <进程名>, <包名>, <设备序列号>.",
      "Do not replace placeholders with fake real values unless the user already provided the value.",
      "Every example must explain the command's purpose in the purpose field.",
      schemaInstruction
    ].join("\n"),
    user: [
      `Mode: ${mode}`,
      `Shell/context: ${shell}`,
      `Task: ${task}`,
      "Input:",
      text
    ].join("\n")
  };
}
