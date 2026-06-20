# terminal-ai-helper

terminal-ai-helper 是一个面向终端命令的 AI 助手。它可以解释命令用法、补全命令、诊断报错，并集成到 PowerShell、SSH 远端 shell、系统托盘和 VS Code 中，让命令行更接近 IDE 里的智能提示体验。

默认使用简体中文回答。示例会用 `<用户名>`、`<主机>`、`<端口>`、`<文件路径>` 这类占位符标出可替换内容，并说明每条命令的作用。

完整说明见：[docs/使用说明.md](docs/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

## 功能

- 解释当前命令、选中文本或剪贴板内容。
- 根据当前输入补全常见命令。
- 诊断命令报错并给出修复建议。
- 提供 PowerShell 快捷键和桌面管理面板。
- 管理面板以独立进程运行，当前终端不会被窗口占住。
- 支持 `brief`、`standard`、`examples`、`custom` 输出风格和自定义输出规则。
- 支持复制剪贴板内容后直接解释或诊断。
- 支持本地 HTTP helper，方便 SSH 远端通过反向隧道使用。
- API key 不写入源码，默认读取用户环境变量或本地配置。

## 命令行用法

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain "ssh <用户名>@<主机> -p <端口>"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete "git log --"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js fix "curl: (35) SSL_connect reset by peer"
```

读取剪贴板：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --clipboard
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js clipboard fix
```

把 AI 结果复制回剪贴板：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --clipboard --copy
```

只输出补全文本：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete --raw "git log --"
```

## PowerShell 桌面用法

最稳的免安装方式：直接运行项目根目录里的启动器，它会打开一个已经加载快捷键的 PowerShell，不需要改 `$PROFILE`：

```powershell
E:\3.13-aliyun-codex\5.2\terminal-ai-helper\terminal-ai-helper.cmd
```

在当前 PowerShell 会话中临时加载：

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

如果想让每个新 PowerShell 自动加载，再安装到 PowerShell 个人配置：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-profile.ps1
```

说明：快捷键本质上是 `PSReadLine` 当前进程里的绑定。外部项目无法凭空接管一个已经打开且没有加载脚本的 PowerShell，所以必须满足以下任一条件：使用 `terminal-ai-helper.cmd` 启动、临时点加载 `. taih-profile.ps1`、或安装到 `$PROFILE` 自动加载。

### 快捷键

不同终端和键盘布局会把 `Alt+Shift+字母` 简化显示成 `Alt+字母`，把 `Alt+Shift+/` 显示成 `Alt+?`。因此请优先按下面“推荐”列使用。

| 推荐快捷键 | 兼容写法 | 功能 |
| --- | --- | --- |
| `Alt+/` | 无 | 解释当前命令行里选中的文本；没有选中时解释当前命令 |
| `Alt+?` | `Alt+Shift+/` | 打开管理面板 |
| `Ctrl+Space` | 无 | 稳定补全：生成 AI 补全文本并直接插入 |
| `Alt+C` | `Alt+Shift+C` | 复制 AI 补全到剪贴板 |
| `Alt+F` | `Alt+Shift+F` | 诊断当前命令或报错 |

备用功能键：

| 快捷键 | 功能 |
| --- | --- |
| `F2` | 解释当前命令 |
| `F3` | 打开管理面板 |
| `F4` | 稳定补全：生成 AI 补全文本并直接插入 |
| `F8` | 诊断当前命令或报错 |

如果某个组合键没反应，运行 `taih-what-key`，然后按下那个快捷键，查看 PowerShell 实际收到的键名。运行 `taih-keys` 可以查看当前已注册的快捷键。

可编辑补全候选框保留为实验入口，不再默认绑定到快捷键，避免影响稳定路径：

```powershell
taih-complete-popup
```

### 常用命令别名

```powershell
taih-current                  # 解释当前命令
taih-panel                    # 打开管理面板
taih-popup                    # 使用当前命令打开面板
taih-clip                     # 解释剪贴板内容
taih-clip -Mode fix -Window   # 在面板里诊断剪贴板里的报错
taih-clip -Mode explain -Copy # 解释剪贴板内容并把结果复制回剪贴板
```

### 选中文本规则

1. 如果在 PowerShell 当前可编辑命令行里选中了文本，优先使用选中文本。
2. 如果没有选中，使用当前光标前的命令。
3. 如果要解释终端历史输出，先选中输出并按 `Ctrl+C`，再运行 `taih-clip` 或 `taih-clip -Window`。

管理面板会作为独立 PowerShell 窗口运行，并尽量无缝拼接到当前终端窗口右侧；如果右侧空间不足，会贴到终端另一侧。面板会跟随当前终端移动，终端窗口关闭时面板也会自动关闭。同一个终端重复按快捷键会复用已有面板并更新内容。当前终端只负责唤起面板，之后可以继续输入和执行命令。

面板默认使用 `brief` 输出风格，避免解释太长。顶部可以选择：

| 模式 | 适合场景 |
| --- | --- |
| `explain（解析命令）` | 解析命令含义、参数、示例和风险 |
| `fix（诊断报错）` | 诊断报错和给修复步骤 |
| `complete（补全命令）` | 根据当前输入补全命令 |

| 风格 | 适合场景 |
| --- | --- |
| `brief（简洁）` | 日常查命令，最多保留关键用法和少量示例 |
| `standard（标准）` | 需要常规解释、风险和下一步 |
| `examples（示例优先）` | 只想看可复制示例 |
| `custom（按规则）` | 使用你在规则框里写的格式要求 |

规则框可以写自定义提示词。默认会要求段落之间留一个空行、列表和示例使用两个空格缩进，避免内容挤在一起。例如：

```text
只输出三段：作用、最常用参数、两个示例。
不要输出长表格。
示例必须使用 <文件路径>、<主机> 这类占位符。
```

CLI 也支持同一套格式控制：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --style brief -- "git status"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --style custom --instructions-file .\my-rules.txt -- "ssh <用户名>@<主机>"
```

面板左侧窄栏是历史记录，点击历史项会回填命令；如果历史里保存了输出，也会直接显示。历史区默认较窄，优先把空间留给输出区。同一个终端再次使用 `Alt+?`、`Alt+Shift+/` 或 `taih-panel` 时，默认更新这块面板，不再反复弹出新窗口。

`Ctrl+Space` 和 `F4` 使用稳定补全路径：生成 AI 补全文本后直接插入当前命令行。可编辑候选框可以通过 `taih-complete-popup` 手动打开。

缓存分两层：

- `git`、`ssh`、`docker` 这类常见命令在 `brief explain` 下会先走本地快速解释，首次也不用等 API。
- 其他命令的流式结果会写入本地缓存；再次查询相同命令和相同输出规则时会直接返回缓存。

## 系统托盘常驻

安装开机自启托盘：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-tray-startup.ps1
```

立即启动托盘：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

托盘可以直接打开面板、解释剪贴板、诊断剪贴板，并启动 SSH helper server。这样即使当前 PowerShell 会话没有加载快捷键，也可以使用主要功能。

## SSH 远端使用

进入 SSH 会话后，本地 PowerShell 快捷键不会再接管命令行，因为当前输入已经由远端 shell 处理。

推荐方式：API key 留在本机，本机启动 helper server，然后通过 SSH 反向隧道给远端使用。

1. 本机启动 helper server：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
```

2. 使用反向隧道连接服务器：

```powershell
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

3. 在远端加载 bash 集成：

```bash
source /path/to/terminal-ai-helper/remote/taih-bash.sh
```

远端快捷键：

| 快捷键 | 功能 |
| --- | --- |
| `Alt+/` | 解释远端当前命令 |
| `Alt+?` | 把远端当前命令发送到本机管理面板 |
| `Ctrl+Space` | 补全远端当前命令 |
| `Alt+F` | 诊断远端当前命令 |

手动使用：

```bash
taih explain 'systemctl status <服务名>'
taih fix 'Permission denied (publickey)'
journalctl -u <服务名> -n 80 --no-pager | taih fix
taih-panel explain 'systemctl status <服务名>'
journalctl -u <服务名> -n 80 --no-pager | taih-panel fix
```

说明：远端 shell 不能直接读取你在 Windows Terminal 里用鼠标选中的文本，因为选区属于本机终端 UI，不属于服务器 bash/readline。推荐做法是用管道或 `taih-panel` 把文本发回本机，本机保留 API key 并负责展示面板。

如果远端快捷键没反应，先在服务器里运行：

```bash
taih-keys
```

常见原因：

- 当前不是交互式 `bash`，`bind -x` 不生效；可以改用 `taih ...` 或 `taih-panel ...` 命令。
- 没有在当前 SSH 会话里执行 `source /path/to/terminal-ai-helper/remote/taih-bash.sh`。
- Windows Terminal、输入法或远端程序抢走了 `Ctrl+Space` / `Alt+F`。远端脚本同时支持 `Alt+F` 和 `Alt+f`，也可以直接用命令兜底。
- 本机没有启动 `node ...\taih.js serve --port 17888`，或 SSH 没带 `-R 17888:127.0.0.1:17888`。

如果不想在服务器上安装任何内容，可以把远端终端输出复制到本机，然后在本机 PowerShell 中运行：

```powershell
taih-clip -Window
```

## API 配置

默认配置：

```text
TAIH_BASE_URL=https://qyapi.cjyyswq.com
TAIH_MODEL=gpt-5.5
OPENAI_API_KEY=<你的中转站 API key>
```

安全写入当前 Windows 用户环境变量：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-user-env.ps1
```

然后重新打开 PowerShell，运行：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
```

`doctor` 应该显示：

```text
baseUrl: https://qyapi.cjyyswq.com
apiKey: found
```

## 测试

```powershell
cd E:\3.13-aliyun-codex\5.2\terminal-ai-helper
npm run check
powershell -NoProfile -ExecutionPolicy Bypass -File .\powershell\test-panel.ps1
```

`test-panel.ps1` 会检查 PowerShell 脚本语法、快捷键绑定、别名、空输入处理，以及真实异步面板请求。

## 安全提醒

不要把 API key 提交到仓库。请放在用户环境变量或本地密钥配置中。已经公开过的 key 应该立即在中转站后台作废并重新生成。
