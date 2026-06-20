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

const defaultToolset = "auto,linux,ssh,git,docker,k8s,python,node,java,adb";

const schemaInstruction = `只返回紧凑 JSON，不要输出 Markdown，不要包裹代码块。JSON 结构必须是：
{
  "title": "简短中文标题",
  "summary": "一句话说明",
  "confidence": "high|medium|low",
  "completion": "最佳补全文本；如果不适合补全则留空",
  "completions": ["3 到 8 条可直接使用或继续编辑的完整命令"],
  "usage": ["清晰的常规用法"],
  "examples": [
    {
      "command": "可复制命令，变量必须使用 ${placeholders} 这类占位符",
      "purpose": "这条命令的作用"
    }
  ],
  "related_commands": [
    {
      "command": "和当前命令高度相关的命令",
      "purpose": "这条命令能解决什么",
      "when": "什么时候用"
    }
  ],
  "risks": ["风险或安全提醒"],
  "next_steps": ["可以继续做的下一步"]
}`;

function normalizeTools(tools = "") {
  const value = String(tools || "").trim();
  return value || process.env.TAIH_TOOLS || defaultToolset;
}

function styleInstructions(outputStyle = "standard", extraInstructions = "") {
  const style = String(outputStyle || "standard").toLowerCase();
  const rules = {
    brief: [
      "输出要短，默认控制在可扫读范围；如果内容很多，优先给最相关的 3 到 5 条。",
      "顺序固定为：作用、常用用法、相关命令、示例、风险提醒。",
      "段落之间保留一个空行。",
      "列表和示例说明使用两个空格缩进。",
      "不要输出长表格、完整参数手册或背景长文。"
    ],
    standard: [
      "输出要实用，不要啰嗦。",
      "优先使用短列表，不写长段落。",
      "段落之间保留一个空行，命令和说明之间留出可读间距。",
      "解析命令时，除了说明当前命令，也给出和当前工具/资源高度相关的常用命令。"
    ],
    examples: [
      "重点给可复制示例。",
      "变量部分必须使用占位符。",
      "每个示例用一句话说明作用。",
      "示例之间保留空行，便于扫读。"
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
      explain: "解释这条终端命令。说明作用、常用参数、示例、风险，并给出和当前命令高度相关的后续命令。",
      complete: "补全当前终端命令前缀。给出安全、常规、实用的候选命令；不要只给 --help。",
      fix: "诊断这条命令或报错的原因，并给出修复步骤和验证命令。",
      tools: "根据当前工具集生成常用命令菜单。默认只列最高频入口：每个工具 3 到 5 条命令，说明用途、常见排查入口和风险提醒。"
    }[mode];
  }
  return {
    explain: "解释这条终端命令的作用、常规用法、参数、示例、风险，并补充高度相关命令。",
    complete: "补全当前终端命令。先给出建议补全文本，再简短说明原因。",
    fix: "诊断这条命令或报错的原因，并给出明确修复步骤。",
    tools: "生成当前工具集的常用命令菜单，按工具分组，命令可复制，说明简短；默认不要写成长手册。"
  }[mode];
}

function baseSystem(outputStyle, extraInstructions, structured, tools) {
  const toolset = normalizeTools(tools);
  const lines = [
    "你是资深终端命令助手，熟悉 Windows PowerShell、CMD、Linux shell、Git、SSH、Python、Java、Node.js、Docker、Kubernetes、Android/ADB 和嵌入式开发。",
    "必须用简体中文回答。",
    `当前优先工具集：${toolset}。如果工具集是 auto，请从输入命令判断最相关工具。`,
    "回答要简洁、实用、安全。",
    "不要建议破坏性命令，除非用户明确要求；如果命令可能删除数据、覆盖文件或停止服务，必须明确提醒。",
    "补全命令时保留用户意图，不要编造私有路径、真实密钥、真实账号或真实主机。",
    "complete 模式必须给出多条实际候选命令，不要只给 --help。",
    `示例里的可变内容必须使用尖括号占位符，例如 ${placeholders}。`,
    "不要用假真实值替代占位符，除非用户输入里已经提供了该值。",
    "每个示例和相关命令都必须说明作用。",
    "如果输入来自选中文本，把选中文本作为当前上下文解释。",
    "解析 Kubernetes 这类资源命令时，要补充与资源强相关的命令。例如 kube get svc 应给出按命名空间、全命名空间、wide/yaml、describe、endpoints、pods 等相关命令。",
    "tools 模式默认生成菜单，不生成完整手册；除非用户自定义规则要求展开，否则控制在可扫读范围内。",
    ...styleInstructions(outputStyle, extraInstructions)
  ];
  if (structured) lines.push(schemaInstruction);
  return lines.join("\n");
}

export function buildPrompt({
  mode,
  text,
  shell,
  source = "typed text",
  outputStyle = "standard",
  extraInstructions = "",
  tools = ""
}) {
  return {
    system: baseSystem(outputStyle, extraInstructions, true, tools),
    user: [
      `模式: ${mode}`,
      `Shell/上下文: ${shell}`,
      `输入来源: ${source}`,
      `工具集: ${normalizeTools(tools)}`,
      `任务: ${taskFor(mode, true)}`,
      "输入:",
      text
    ].join("\n")
  };
}

export function buildPlainPrompt({
  mode,
  text,
  shell,
  source = "typed text",
  outputStyle = "standard",
  extraInstructions = "",
  tools = ""
}) {
  return {
    system: baseSystem(outputStyle, extraInstructions, false, tools),
    user: [
      `模式: ${mode}`,
      `Shell/上下文: ${shell}`,
      `输入来源: ${source}`,
      `工具集: ${normalizeTools(tools)}`,
      `任务: ${taskFor(mode, false)}`,
      "输入:",
      text
    ].join("\n")
  };
}
