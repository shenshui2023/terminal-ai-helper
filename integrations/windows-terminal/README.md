# Windows Terminal 集成

Windows Terminal 目前不提供第三方项目直接扩展右键菜单的稳定接口，所以这里采用两个可落地入口。

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

这个方式只复制你当前选中的文本，API key 留在本机，不需要在服务器安装密钥。

注意：全局热键会向当前窗口发送一次 `Ctrl+C` 来复制选区。请先选中文本再按热键；如果没有选区，远端 shell 可能会把 `Ctrl+C` 当作中断。

## 可选：Windows Terminal actions

可以在 Windows Terminal 的 `settings.json` 里添加动作，快速启动托盘程序或打开项目面板。

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

如果你主要在 SSH 里工作，建议使用托盘全局选区快捷键；如果需要远端命令行里直接补全当前输入，再使用项目 README 里的 SSH 反向隧道方案。
