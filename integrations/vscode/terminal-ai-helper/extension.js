const cp = require("child_process");
const vscode = require("vscode");

let channel;

function getSelectionText() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return "";
  const selection = editor.selection;
  if (selection.isEmpty) return "";
  return editor.document.getText(selection);
}

function runHelper(mode, text) {
  const config = vscode.workspace.getConfiguration("terminalAiHelper");
  const cliPath = config.get("cliPath");
  if (!cliPath) {
    vscode.window.showErrorMessage("尚未配置 terminalAiHelper.cliPath。");
    return;
  }

  if (!channel) channel = vscode.window.createOutputChannel("终端 AI 助手");
  channel.show(true);
  channel.appendLine(`正在执行 ${mode}...`);
  channel.appendLine("");

  const started = Date.now();
  const child = cp.spawn("node", [cliPath, mode, "--", text], {
    windowsHide: true,
    env: process.env
  });

  child.stdout.on("data", (chunk) => channel.append(chunk.toString("utf8")));
  child.stderr.on("data", (chunk) => channel.append(chunk.toString("utf8")));
  child.on("close", (code) => {
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    channel.appendLine("");
    channel.appendLine(`完成，用时 ${seconds} 秒，退出码 ${code}`);
  });
}

function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.explainSelection", () => {
    const text = getSelectionText();
    if (!text) return vscode.window.showWarningMessage("没有选中文本。");
    runHelper("explain", text);
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.fixSelection", () => {
    const text = getSelectionText();
    if (!text) return vscode.window.showWarningMessage("没有选中文本。");
    runHelper("fix", text);
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.explainClipboard", async () => {
    const text = await vscode.env.clipboard.readText();
    if (!text) return vscode.window.showWarningMessage("剪贴板为空。");
    runHelper("explain", text);
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
