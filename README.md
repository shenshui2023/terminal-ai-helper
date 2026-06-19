# terminal-ai-helper

一个给终端用的 AI 命令助手：根据当前命令解释常规用法、风险、示例，也可以像 IDE 一样对当前命令行做补全建议。

## 功能

- `taih explain <命令>`：解释命令、参数、常见用法和风险。
- `taih complete <命令前缀>`：返回适合追加到当前命令后的补全文本。
- `taih fix <错误信息>`：根据报错给出原因和修复步骤。
- 示例会使用 `<用户名>`、`<主机>`、`<端口>`、`<文件路径>` 这类占位标签表示可变内容，并说明每条命令的作用。
- PowerShell 快捷键：
  - `Alt+/`：解释当前正在输入的命令。
  - `Ctrl+Space`：根据当前命令插入 AI 补全。

## API 配置

默认读取：

- `TAIH_BASE_URL=https://qyapi.cjyyswq.com`
- `TAIH_MODEL=gpt-5.5`
- `OPENAI_API_KEY`

如果没有 `OPENAI_API_KEY`，会自动读取：

```text
%USERPROFILE%\.codex\auth.json
```

源码不会保存 API key。

如果 `doctor` 显示从 `auth.json:tokens.access_token` 读取到凭据，但真实请求报 `INVALID_API_KEY`，说明代理 API 不接受 Codex 登录 token。请设置真正的 API key：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-user-env.ps1
```

设置后重新打开 PowerShell。

## 使用

在项目目录运行：

```powershell
cd E:\3.13-aliyun-codex\5.2\terminal-ai-helper
npm run check
node .\bin\taih.js doctor
node .\bin\taih.js explain "ssh root@43.112.115.205"
node .\bin\taih.js complete "git log --"
```

临时加载 PowerShell 集成：

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

长期加载可以把上面这一行加入你的 PowerShell profile：

```powershell
notepad $PROFILE
```

## 安全习惯

不要把 API key 写进仓库。建议只放在环境变量或 `%USERPROFILE%\.codex\auth.json`。
