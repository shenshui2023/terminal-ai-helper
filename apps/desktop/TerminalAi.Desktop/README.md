# TerminalAi.Desktop

TerminalAi.Desktop 是 terminal-ai-helper 的 C# 桌面常驻程序，目标是接管桌面交互：

- 系统托盘菜单
- 全局快捷键
- 当前 Windows Terminal 文本读取
- 补全结果写回终端
- 启动/停止本地 helper server
- 打开管理面板、补全弹窗、SSH 面板

核心 AI 能力仍然在 Node.js 的 `src/` 和 `apps/cli/` 中。桌面端不直接实现 API 请求、缓存和提示词，避免桌面 UI 和核心能力耦合。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Alt+P` | 补全当前终端输入 |
| `Ctrl+Alt+E` | 解释当前终端输入 |
| `Ctrl+Alt+/` | 解释当前选中文本 |
| `Ctrl+Alt+F` | 诊断当前选中文本 |

## 运行

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\desktop.ps1
```

关闭：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\desktop.ps1 -Stop
```

## 开机启动

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install\desktop-startup.ps1 -Build
```

## 卸载本地集成

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

## 当前过渡策略

TerminalAi.Desktop 当前会通过 `PowerShellBridge` 调用旧的 PowerShell 面板和补全弹窗。这样可以先稳定桌面入口和热键，再逐步把面板改成原生 C#。

后续替换路径：

```text
PowerShellBridge
  -> C# NativePanelService
  -> C# NativeCompletionPopup
```

替换时不需要改 `src/core`、`src/ai`、`src/server`。
