const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const vscode = require("vscode");

let channel;

function getConfig() {
  const config = vscode.workspace.getConfiguration("terminalAiHelper");
  return {
    cliPath: config.get("cliPath"),
    defaultStyle: config.get("defaultStyle") || "brief",
    usePanelByDefault: Boolean(config.get("usePanelByDefault"))
  };
}

function projectRootFromCli(cliPath) {
  return path.resolve(path.dirname(cliPath), "..");
}

function getSelectionText() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return "";
  const selection = editor.selection;
  if (selection.isEmpty) return "";
  return editor.document.getText(selection);
}

function ensureCliPath(cliPath) {
  if (!cliPath) {
    vscode.window.showErrorMessage("尚未配置 terminalAiHelper.cliPath。");
    return false;
  }
  if (!fs.existsSync(cliPath)) {
    vscode.window.showErrorMessage(`找不到 taih.js：${cliPath}`);
    return false;
  }
  return true;
}

function runHelperOutput(mode, text) {
  const config = getConfig();
  if (!ensureCliPath(config.cliPath)) return;

  if (!channel) channel = vscode.window.createOutputChannel("终端 AI 助手");
  channel.show(true);
  channel.appendLine(`正在执行 ${mode}，结果会流式输出...`);
  channel.appendLine("");

  const started = Date.now();
  const child = cp.spawn("node", [
    config.cliPath,
    mode,
    "--stream",
    "--style",
    config.defaultStyle,
    "--",
    text
  ], {
    windowsHide: true,
    env: process.env
  });

  child.stdout.on("data", (chunk) => channel.append(chunk.toString("utf8")));
  child.stderr.on("data", (chunk) => channel.append(chunk.toString("utf8")));
  child.on("error", (error) => vscode.window.showErrorMessage(`启动失败：${error.message}`));
  child.on("close", (code) => {
    const seconds = ((Date.now() - started) / 1000).toFixed(1);
    channel.appendLine("");
    channel.appendLine(`完成，用时 ${seconds} 秒，退出码 ${code}`);
  });
}

function openLocalPanel(mode, text) {
  const config = getConfig();
  if (!ensureCliPath(config.cliPath)) return;

  const root = projectRootFromCli(config.cliPath);
  const panelScript = path.join(root, "apps", "powershell", "panel.ps1");
  if (!fs.existsSync(panelScript)) {
    vscode.window.showErrorMessage(`找不到面板脚本：${panelScript}`);
    return;
  }

  const inputFile = path.join(os.tmpdir(), `taih-vscode-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`);
  fs.writeFileSync(inputFile, text, "utf8");

  const child = cp.spawn("powershell.exe", [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    panelScript,
    "-InputFile",
    inputFile,
    "-Mode",
    mode,
    "-PanelId",
    "vscode",
    "-AnchorX",
    "-1",
    "-AnchorY",
    "-1",
    "-AnchorW",
    "-1",
    "-AnchorH",
    "-1"
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  });
  child.unref();
  vscode.window.setStatusBarMessage("终端 AI 助手面板已打开", 2500);
}

function runFromText(mode, text, panel = false) {
  if (!text.trim()) {
    vscode.window.showWarningMessage("没有可分析的文本。");
    return;
  }
  if (panel || getConfig().usePanelByDefault) {
    openLocalPanel(mode, text);
  } else {
    runHelperOutput(mode, text);
  }
}

async function runFromClipboard(mode, panel = false) {
  const text = await vscode.env.clipboard.readText();
  runFromText(mode, text, panel);
}

function activate(context) {
  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.explainSelection", () => {
    runFromText("explain", getSelectionText());
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.fixSelection", () => {
    runFromText("fix", getSelectionText());
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.explainClipboard", () => {
    runFromClipboard("explain");
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.fixClipboard", () => {
    runFromClipboard("fix");
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.openPanelSelection", () => {
    runFromText("explain", getSelectionText(), true);
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.openPanelClipboard", () => {
    runFromClipboard("explain", true);
  }));

  context.subscriptions.push(vscode.commands.registerCommand("terminalAiHelper.openSettings", () => {
    vscode.commands.executeCommand("workbench.action.openSettings", "terminalAiHelper");
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
