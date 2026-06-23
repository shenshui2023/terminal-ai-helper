# Windows Terminal 集成说明

Windows Terminal 没有稳定的第三方右键菜单扩展接口，所以 terminal-ai-helper 主要通过托盘全局热键和 PowerShell profile 集成。

## 推荐：直接读取当前 SSH 标签页输入

这个方案不需要服务器安装脚本，也不需要 SSH 反向端口。它在本机读取 Windows Terminal 暴露的可访问文本，从最后一行提取正在输入的命令。

启动托盘程序：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

在 Windows Terminal 的 SSH 标签页里使用：

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Alt+P` | 读取当前终端输入，弹出本机智能补全框，选择后写回当前 SSH 命令行 |
| `Ctrl+Alt+E` | 读取当前终端输入，打开本机管理面板解释 |
| `Ctrl+Alt+/` | 解释鼠标选中的文本 |
| `Ctrl+Alt+F` | 诊断鼠标选中的文本 |

如果 `Ctrl+Alt+P/E` 没读到内容，通常是当前终端控件没有暴露可访问文本。此时可以用鼠标选中文本后按 `Ctrl+Alt+/`，或者使用下面的远端 readline 增强。

## 本地 PowerShell 快捷键

当当前标签页是本地 PowerShell，推荐加载 profile：

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

常用键：

| 快捷键 | 功能 |
| --- | --- |
| `F4` 或 `Alt+P` | 补全当前 PowerShell 命令 |
| `Alt+/` | 解释当前 PowerShell 命令 |
| `Alt+?` | 打开管理面板 |

## 可选：远端 readline 增强

只有在本机 UI Automation 读不到当前输入，或你明确需要远端 bash/readline 级别的当前行时，才需要这个方案。

本机：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888 --replace
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端：

```bash
source /path/to/terminal-ai-helper/integrations/ssh/taih-bash.sh
```

远端可用 `F4` 或 `Alt+P` 打开本机补全框。

## 可选：Windows Terminal Actions

可以在 Windows Terminal 的 `settings.json` 里添加 actions，快速启动托盘程序或打开已加载助手的 PowerShell：

```json
{
  "actions": [
    {
      "command": {
        "action": "newTab",
        "commandline": "powershell -NoProfile -ExecutionPolicy Bypass -File E:\\3.13-aliyun-codex\\5.2\\terminal-ai-helper\\powershell\\tray.ps1"
      },
      "name": "启动终端 AI 助手托盘"
    },
    {
      "command": {
        "action": "newTab",
        "commandline": "powershell -NoExit -ExecutionPolicy Bypass -Command \". E:\\3.13-aliyun-codex\\5.2\\terminal-ai-helper\\powershell\\taih-profile.ps1\""
      },
      "name": "打开终端 AI 助手 PowerShell"
    }
  ]
}
```
