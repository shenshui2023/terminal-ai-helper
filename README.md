# terminal-ai-helper

terminal-ai-helper 是一个面向终端命令的 AI 助手。它可以解释命令用法、补全命令、诊断报错，并集成到 PowerShell、SSH 远端 shell、系统托盘和 VS Code 中，让命令行更接近 IDE 里的智能提示体验。

默认使用简体中文回答。示例会用 `<用户名>`、`<主机>`、`<端口>`、`<文件路径>` 这类占位符标出可替换内容，并说明每条命令的作用。

完整说明见：[docs/使用说明.md](docs/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

## 功能

- 解释当前命令、选中文本或剪贴板内容。
- 根据当前输入补全常见命令。
- 诊断命令报错并给出修复建议。
- 提供 PowerShell 快捷键和桌面管理面板。
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

在当前 PowerShell 会话中加载：

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

安装到 PowerShell 个人配置：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-profile.ps1
```

### 快捷键

不同终端和键盘布局会把 `Alt+Shift+字母` 简化显示成 `Alt+字母`，把 `Alt+Shift+/` 显示成 `Alt+?`。因此请优先按下面“推荐”列使用。

| 推荐快捷键 | 兼容写法 | 功能 |
| --- | --- | --- |
| `Alt+/` | 无 | 解释当前命令行里选中的文本；没有选中时解释当前命令 |
| `Alt+?` | `Alt+Shift+/` | 打开管理面板 |
| `Ctrl+Space` | 无 | 生成 AI 补全并插入到光标处 |
| `Alt+C` | `Alt+Shift+C` | 复制 AI 补全到剪贴板 |
| `Alt+F` | `Alt+Shift+F` | 诊断当前命令或报错 |

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

管理面板会在后台执行 API 请求，不会因为等待中转站响应而卡死。输出内容会逐步显示，完成后显示耗时。

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
| `Ctrl+Space` | 补全远端当前命令 |
| `Alt+F` | 诊断远端当前命令 |

手动使用：

```bash
taih explain 'systemctl status <服务名>'
taih fix 'Permission denied (publickey)'
```

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
