# Windows Terminal 集成说明

Windows Terminal 本身没有稳定的第三方右键菜单扩展接口，所以 terminal-ai-helper 提供三种实用入口：

1. 本地 PowerShell 快捷键：适合当前标签页仍由本机 PSReadLine 管理的情况。
2. 托盘全局选区快捷键：适合分析你在 Windows Terminal 里已经选中的文本，包括 SSH 标签页里的远端命令、报错、日志。
3. SSH 远端 bash/readline 集成：适合不选中文本，直接读取远端当前正在编辑的命令行，并把本机补全弹窗作为桌面 UI 使用。

## 托盘全局选区快捷键

启动托盘程序：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

使用方式：

- 在 Windows Terminal 里选中一段命令、报错或日志。
- 按 `Ctrl+Alt+/`：复制选区并打开本机解释面板。
- 按 `Ctrl+Alt+F`：复制选区并打开本机诊断面板。

这个方式读取的是本机 Windows Terminal 选区/剪贴板，API key 留在本机，不需要放到服务器。

注意：全局热键会向当前窗口发送一次 `Ctrl+C` 来复制选区。请先选中文本再按热键；如果没有选区，远端 shell 可能会把 `Ctrl+C` 当作中断。

## SSH 当前命令行补全

进入 SSH 后，你在屏幕上看到的是本机 Windows Terminal 绘制出来的文字，但当前正在编辑的命令行属于远端 bash/readline。本机 PowerShell 的 PSReadLine 不能直接拿到这行输入，所以需要反向隧道：

本机：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端：

```bash
source /path/to/terminal-ai-helper/integrations/ssh/taih-bash.sh
```

远端 `Ctrl+Space` 的实际流程：

1. 远端 bash/readline 读取当前正在编辑的命令行。
2. 通过 `http://127.0.0.1:17888/complete-popup` 发回本机。
3. 本机打开桌面智能补全候选框。
4. 你在本机桌面选择或修改候选。
5. 选择结果返回远端，并替换远端当前命令行。

远端快捷键：

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Space` | 打开本机桌面补全候选框，选择后写回远端当前命令行 |
| `Alt+/` | 解释远端当前命令行 |
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
