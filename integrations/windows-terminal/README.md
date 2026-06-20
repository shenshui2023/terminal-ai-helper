# Windows Terminal 集成

Windows Terminal 目前不提供稳定接口让第三方脚本直接扩展右键菜单，所以项目采用两个可落地入口。

## 推荐：托盘全局选区快捷键

启动托盘常驻程序：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

在 Windows Terminal 里选中任意文本，包括 SSH 远端标签页里的命令、报错、日志，然后：

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Alt+/` | 解释选中文本 |
| `Ctrl+Alt+F` | 诊断选中文本 |

这说明本机确实可以分析你桌面上看到的 SSH 文本：它通过 Windows Terminal 的选区复制来拿文本，API key 留在本机，不需要放到服务器。

注意：全局热键会向当前窗口发送一次 `Ctrl+C` 来复制选区。请先选中文本再按热键；如果没有选区，远端 shell 可能会把 `Ctrl+C` 当作中断。

## 为什么还需要 SSH 远端集成

如果你想分析的是“已经显示出来并被鼠标选中的文本”，用托盘全局选区最合适。

如果你想分析或补全的是“远端 shell 当前正在编辑、但你还没有选中的命令行”，本机 PowerShell 快捷键读不到这段输入。原因是进入 SSH 后，当前输入由 ssh 进程转发给远端 bash/readline，本机 PSReadLine 不再管理这行命令。

这时使用 SSH 反向隧道和远端 `taih-bash.sh`：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端：

```bash
source /path/to/terminal-ai-helper/integrations/ssh/taih-bash.sh
```

## 可选：Windows Terminal actions

可以在 Windows Terminal 的 `settings.json` 里添加动作，快速启动托盘程序或打开已加载助手的 PowerShell。

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
