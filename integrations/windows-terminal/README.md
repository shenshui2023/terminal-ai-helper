# Windows Terminal 集成

Windows Terminal 目前没有稳定接口让第三方脚本直接扩展右键菜单，所以项目提供两种可靠入口：

1. 托盘全局选区快捷键：适合分析你在 Windows Terminal 里已经选中的文本，包括 SSH 标签页里的远端命令、报错、日志。
2. SSH 远端 bash 集成：适合不选中文本，直接读取远端当前正在编辑的命令行，并提供远端补全和命令预测。

## 推荐：托盘全局选区快捷键

启动托盘常驻程序：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

在 Windows Terminal 里选中任意文本，然后：

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Alt+/` | 解释选中文本 |
| `Ctrl+Alt+F` | 诊断选中文本 |

这说明本机确实可以分析你桌面上看到的 SSH 文本：它通过 Windows Terminal 的选区复制拿文本，API key 留在本机，不需要放到服务器。

注意：全局热键会向当前窗口发送一次 `Ctrl+C` 来复制选区。请先选中文本再按热键；如果没有选区，远端 shell 可能会把 `Ctrl+C` 当作中断。

## SSH 当前命令行补全

如果你想分析或补全的是“远端 shell 当前正在编辑、但还没有选中的命令行”，本机 PowerShell 快捷键读不到这段输入。原因是进入 SSH 后，输入由 `ssh` 进程转发给远端 bash/readline，本机 PSReadLine 不再管理这行命令。

这种场景使用 SSH 反向隧道和远端 `taih-bash.sh`：

本机：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端：

```bash
source /path/to/terminal-ai-helper/integrations/ssh/taih-bash.sh
```

远端快捷键：

| 快捷键 | 功能 |
| --- | --- |
| `Alt+/` | 解释远端当前命令行 |
| `Ctrl+Space` | 补全远端当前命令行 |
| `Alt+F` | 诊断远端当前命令行 |
| `Alt+?` | 打开本机管理面板 |
| `Alt+T` | 打开本机工具菜单 |

远端工具集：

```bash
taih-tools
taih-tools linux k8s docker
taih-panel tools
```

`taih-tools linux k8s docker` 会让后续远端解释、补全和工具菜单优先围绕 Linux、Kubernetes、Docker。

## 可选：Windows Terminal actions

可以在 Windows Terminal 的 `settings.json` 里添加 actions，快速启动托盘程序或打开已加载助手的 PowerShell。

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
        "commandline": "powershell -NoProfile -NoExit -Command \". E:\\3.13-aliyun-codex\\5.2\\terminal-ai-helper\\powershell\\taih-profile.ps1\""
      },
      "name": "打开已加载 AI 快捷键的 PowerShell"
    }
  ]
}
```
