const zh = {
  user: "用户名",
  host: "主机",
  port: "端口",
  filePath: "文件路径",
  service: "服务名",
  process: "进程名",
  package: "包名",
  device: "设备序列号",
  namespace: "命名空间"
};

const placeholders = [
  `<${zh.user}>`,
  `<${zh.host}>`,
  `<${zh.port}>`,
  `<${zh.filePath}>`,
  `<${zh.service}>`,
  `<${zh.process}>`,
  `<${zh.package}>`,
  `<${zh.device}>`,
  `<${zh.namespace}>`
].join(", ");

const schemaInstruction = `只返回紧凑 JSON，不要输出 Markdown，不要包裹代码块。JSON 结构必须是：
{
  "title": "简短中文标题",
  "summary": "一句话说明",
  "confidence": "high|medium|low",
  "completion": "最佳补全文本；如果不适合补全则留空",
  "completions": ["3 到 6 条可直接使用或继续编辑的完整命令"],
  "usage": ["清晰的常规用法"],
  "examples": [
    {
      "command": "可复制命令，变量必须使用 ${placeholders} 这类占位符",
      "purpose": "这条命令的作用"
    }
  ],
  "risks": ["风险或安全提醒"],
  "next_steps": ["可以继续做的下一步"]
}`;

function styleInstructions(outputStyle = "standard", extraInstructions = "") {
  const style = String(outputStyle || "standard").toLowerCase();
  const rules = {
    brief: [
      "输出必须简短：最多 8 行。",
      "顺序固定为：作用、常用用法、最多 2 个示例、有风险才提醒。",
      "段落之间保留一个空行。",
      "列表和示例说明使用两个空格缩进。",
      "不要输出长表格、完整参数手册或背景长文。"
    ],
    standard: [
      "输出要实用，不要啰嗦。",
      "优先使用短列表，不写长段落。",
      "段落之间保留一个空行，缩进要方便阅读。",
      "只有示例能明显澄清用法时才给示例。"
    ],
    examples: [
      "重点给可复制示例。",
      "变量部分必须使用占位符。",
      "每个示例用一句话说明作用。",
      "超过四行时，示例之间保留空行。"
    ],
    custom: [
      "严格遵守用户自定义输出规则，前提是规则安全。",
      "如果初稿不符合规则，必须重写到符合规则。",
      "除非自定义规则明确要求，否则保持空行和缩进可读。"
    ]
  }[style] || [];

  const custom = String(extraInstructions || "").trim();
  if (custom) {
    rules.push("用户自定义输出规则：");
    rules.push(custom);
  }
  return rules;
}

function taskFor(mode, structured) {
  if (structured) {
    return {
      explain: "解释这条终端命令。说明作用、常用参数、示例和风险。",
      complete: "补全当前终端命令前缀。给出安全、常规、实用的候选命令。",
      fix: "诊断这条命令或报错的原因，并给出修复步骤。"
    }[mode];
  }
  return {
    explain: "解释这条终端命令的作用、常规用法、参数、示例和风险。",
    complete: "补全当前终端命令。先给出建议补全文本，再简短说明原因。",
    fix: "诊断这条命令或报错的原因，并给出明确修复步骤。"
  }[mode];
}

function baseSystem(outputStyle, extraInstructions, structured) {
  const lines = [
    "你是资深终端命令助手，熟悉 Windows PowerShell、CMD、Linux shell、Git、SSH、Python、Java、Node.js、Docker、Kubernetes、Android/ADB 和嵌入式开发。",
    "必须用简体中文回答。",
    "回答要简洁、实用、安全。",
    "不要建议破坏性命令，除非用户明确要求；如果命令可能删除数据、覆盖文件或停止服务，必须明确提醒。",
    "补全命令时保留用户意图，不要编造私有路径、真实密钥、真实账号或真实主机。",
    "complete 模式必须给出多条实际候选命令，不要只给 --help。",
    `示例里的可变内容必须使用尖括号占位符，例如 ${placeholders}。`,
    "不要用假真实值替代占位符，除非用户输入里已经提供了该值。",
    "每个示例都必须说明作用。",
    "如果输入来自选中文本，把选中文本作为当前上下文解释。",
    ...styleInstructions(outputStyle, extraInstructions)
  ];
  if (structured) lines.push(schemaInstruction);
  return lines.join("\n");
}

export function buildPrompt({ mode, text, shell, source = "typed text", outputStyle = "standard", extraInstructions = "" }) {
  return {
    system: baseSystem(outputStyle, extraInstructions, true),
    user: [
      `模式: ${mode}`,
      `Shell/上下文: ${shell}`,
      `输入来源: ${source}`,
      `任务: ${taskFor(mode, true)}`,
      "输入:",
      text
    ].join("\n")
  };
}

export function buildPlainPrompt({ mode, text, shell, source = "typed text", outputStyle = "standard", extraInstructions = "" }) {
  return {
    system: baseSystem(outputStyle, extraInstructions, false),
    user: [
      `模式: ${mode}`,
      `Shell/上下文: ${shell}`,
      `输入来源: ${source}`,
      `任务: ${taskFor(mode, false)}`,
      "输入:",
      text
    ].join("\n")
  };
}
