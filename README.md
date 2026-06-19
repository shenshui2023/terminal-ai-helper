# terminal-ai-helper

AI assistance for terminal commands. It explains command usage, suggests completions, diagnoses errors, and integrates with PowerShell so it can work more like an IDE helper for the command line.

中文使用说明见：[docs/使用说明.md](docs/%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E.md)

The assistant answers in Simplified Chinese by default. Examples use placeholders for variable parts, such as `<username>`, `<host>`, `<port>`, and `<file-path>`, and each example explains what the command does.

## Features

- Explain the current command, selected text, or clipboard text.
- Suggest safe command completions.
- Diagnose command errors.
- PowerShell hotkeys for a desktop-like workflow.
- Optional native popup window for longer explanations.
- Reused desktop panel with visible working state and elapsed time.
- Clipboard input and output support.
- Local HTTP helper for SSH reverse-tunnel use.
- No source-code storage of API keys.

## CLI Usage

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain "ssh <username>@<host> -p <port>"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete "git log --"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js fix "curl: (35) SSL_connect reset by peer"
```

Read from clipboard:

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --clipboard
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js clipboard fix
```

Copy the AI result back to clipboard:

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --clipboard --copy
```

Print only the completion text:

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete --raw "git log --"
```

## PowerShell Desktop Workflow

Load once in the current PowerShell session:

```powershell
. E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\taih-profile.ps1
```

Install into your PowerShell profile:

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-profile.ps1
```

Hotkeys:

| Hotkey | Action |
| --- | --- |
| `Alt+/` | Explain selected text, or the current command before the cursor. |
| `Alt+Shift+/` | Open or update the persistent helper panel. |
| `Ctrl+Space` | Insert AI completion at the cursor. |
| `Alt+Shift+C` | Copy AI completion to clipboard. |
| `Alt+Shift+F` | Diagnose selected text, or the current command before the cursor. |

Commands:

```powershell
taih-current
taih-popup
taih-clip
taih-clip -Mode fix -Window
taih-clip -Mode explain -Copy
```

Selection behavior:

1. If text is selected inside the editable PowerShell command line, that selected text is used.
2. Otherwise, the helper uses the current command before the cursor.
3. For text selected from terminal output, press `Ctrl+C` first, then run `taih-clip` or `taih-clip -Window`.

The panel is reused instead of creating a new window each time. It shows `Working...` before the API call starts and shows elapsed time after the result arrives.

## SSH Remote Shell Usage

PowerShell hotkeys do not work after you enter an SSH session because the active command line is now handled by the remote shell, not local PSReadLine.

Recommended solution: keep the API key on your local machine, expose a local helper server to the remote host through an SSH reverse tunnel, and load the remote bash bindings.

1. Start the local helper server in a local PowerShell window:

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888
```

2. Connect with a reverse tunnel:

```powershell
ssh -R 17888:127.0.0.1:17888 <username>@<host>
```

3. Copy or clone this project on the remote host, then load the bash integration:

```bash
source /path/to/terminal-ai-helper/remote/taih-bash.sh
```

Remote hotkeys:

| Hotkey | Action |
| --- | --- |
| `Alt+/` | Explain current remote command line. |
| `Ctrl+Space` | Complete current remote command line. |
| `Alt+F` | Diagnose current remote command line. |

Manual remote use:

```bash
taih explain 'systemctl status <service-name>'
taih fix 'Permission denied (publickey)'
```

If you do not want to install anything on the server, copy selected terminal text locally with `Ctrl+C`, return to a local PowerShell prompt, and run:

```powershell
taih-clip -Window
```

## API Configuration

Default values:

```text
TAIH_BASE_URL=https://qyapi.cjyyswq.com
TAIH_MODEL=gpt-5.5
OPENAI_API_KEY=<your-api-key>
```

Set user environment variables safely:

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-user-env.ps1
```

Then restart PowerShell and run:

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js doctor
```

## Development

```powershell
cd E:\3.13-aliyun-codex\5.2\terminal-ai-helper
npm run check
```

## Safety

Do not commit API keys. Keep them in user environment variables or another local secret store.
