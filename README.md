# terminal-ai-helper

一个面向 Windows 终端的 AI 命令助手。它可以解释命令、诊断报错、补全当前命令，并提供一个停靠在终端右侧的管理面板。

## 主要功能

- `Ctrl+Space` 在当前终端光标附近打开智能补全候选框。
- 候选框会先显示本地快速建议，`git`、`ssh`、`docker`、`npm`、`python`、`java`、`adb` 这类命令不用先等 API。
- AI 候选会在后台补充进列表；如果中转站临时失败，会保留本地候选并在状态栏显示失败原因。
- 选中候选后，可以在下方输入框直接修改完整命令，再按 `Enter` 插回当前命令行。
- `complete` 结果会写入本地缓存，重复补全会更快。
- 管理面板会尽量贴在当前终端右侧，复用同一个窗口，并提供历史记录、输出格式、提示词规则、剪贴板读取和缓存清理。

## 安装

进入项目目录：

```powershell
cd E:\3.13-aliyun-codex\5.2\terminal-ai-helper
```

检查 Node.js 可用：

```powershell
node .\bin\taih.js doctor
```

在当前 PowerShell 会话中加载快捷键：

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

如果要写入 PowerShell profile，让以后打开终端自动加载：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-profile.ps1
```

## API 配置

推荐使用中转站，不要把 API key 写进项目源码。

可以写入当前 Windows 用户环境变量：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-user-env.ps1
```

也可以使用环境变量：

```powershell
[Environment]::SetEnvironmentVariable("TAIH_BASE_URL", "https://qyapi.cjyyswq.com", "User")
[Environment]::SetEnvironmentVariable("TAIH_MODEL", "gpt-5.5", "User")
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "<你的中转站 API key>", "User")
```

重新打开 PowerShell 后检查：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
```

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Alt+/` | 解释选中文本或当前命令 |
| `Alt+?` | 打开管理面板，很多键盘上 `Alt+Shift+/` 会被识别为 `Alt+?` |
| `Ctrl+Space` | 打开智能补全候选框 |
| `Alt+C` | 复制 AI 补全 |
| `Alt+F` | 诊断选中文本或当前命令 |
| `F2` | 备用：解释当前命令 |
| `F3` | 备用：打开管理面板 |
| `F4` | 备用：打开智能补全候选框，和 `Ctrl+Space` 相同 |
| `F8` | 备用：诊断当前命令 |

如果某个组合键没有反应，先运行：

```powershell
taih-keys
taih-what-key
```

`taih-what-key` 会让 PSReadLine 显示终端实际收到的按键名。Windows Terminal、输入法、远端 SSH 会话都可能抢占组合键。

## 常用命令

```powershell
taih-current                  # 解释当前命令
taih-panel                    # 打开或更新右侧管理面板
taih-popup                    # 使用当前命令打开管理面板
taih-complete-popup           # 手动打开可编辑补全候选框
taih-complete-stable          # 不弹窗，直接请求 AI 并插入补全
taih-clip                     # 解释剪贴板内容
taih-clip -Mode fix -Window   # 在面板里诊断剪贴板里的报错
taih-panel-reset              # 清理卡住的面板状态
```

CLI 示例：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --style brief -- "git status"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete --json -- "ssh"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache clear
```

## 补全候选框

在命令行输入一部分命令，例如：

```powershell
ssh
```

按 `Ctrl+Space` 后会出现候选框：

- 上方列表显示候选命令。
- 下方输入框可以直接修改当前候选。
- `Enter` 插回当前命令行。
- `Esc` 关闭。
- `复制` 只复制候选，不修改当前命令行。

本地候选立即显示，AI 候选后台补充。重复相同补全时会命中缓存。

## 管理面板

运行：

```powershell
taih-panel
```

面板默认贴在当前终端右侧，并尽量和终端一起移动、一起关闭。同一个终端重复调用会复用原面板并更新内容。

面板里的模式：

| 模式 | 说明 |
| --- | --- |
| `explain（解析命令）` | 解释命令含义、参数、示例和风险 |
| `fix（诊断报错）` | 分析报错原因并给出修复步骤 |
| `complete（补全命令）` | 根据当前输入补全命令 |

输出风格：

| 风格 | 说明 |
| --- | --- |
| `brief（简洁）` | 日常查命令，短输出 |
| `standard（标准）` | 常规解释、风险和下一步 |
| `examples（示例优先）` | 多给可复制示例 |
| `custom（按规则）` | 按规则框里的自定义提示词输出 |

规则框可以写你的格式要求，例如：

```text
只输出三段：作用、最常用参数、两个示例。
示例必须使用 <文件路径>、<用户名>、<主机> 这类占位符。
不要输出长表格。
```

面板默认隐藏历史记录区，把空间留给输出文本。点击底部 `历史` 按钮可以展开历史栏；点击历史项会回填命令，如果历史里保存了输出，也会直接显示。

## SSH 远端使用

进入 SSH 会话后，本地 PowerShell 快捷键通常不会再接管命令行，因为当前输入已经由远端 shell 处理。

推荐方案是 API key 留在本机，本机启动 helper server，然后通过 SSH 反向隧道给远端使用：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端加载 bash 集成：

```bash
source /path/to/terminal-ai-helper/remote/taih-bash.sh
```

远端也可以手动把文本发回本机面板：

```bash
taih explain 'systemctl status <服务名>'
journalctl -u <服务名> -n 80 --no-pager | taih fix
taih-panel explain 'systemctl status <服务名>'
journalctl -u <服务名> -n 80 --no-pager | taih-panel fix
```

## 测试

```powershell
npm run check
powershell -NoProfile -ExecutionPolicy Bypass -File .\powershell\test-panel.ps1 -SkipApi
```

`test-panel.ps1` 会检查：

- PowerShell 脚本能解析和加载。
- 快捷键和别名已注册。
- 本地补全候选可用。
- 补全候选框能在无 API 模式下返回本地候选。
- 管理面板子进程能启动并保持存活。

## 故障处理

面板没反应：

```powershell
taih-panel-reset
taih-panel
```

快捷键没反应：

```powershell
taih-keys
taih-what-key
```

API 不通：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
```

清理缓存：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache clear
```
