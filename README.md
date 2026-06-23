# terminal-ai-helper

一个面向 Windows 终端的 AI 命令助手。它可以解释命令、诊断报错、补全当前命令，并提供一个停靠在终端右侧的管理面板。

项目结构说明见：[docs/项目结构.md](docs/项目结构.md)。

## 主要功能

- 本地 PowerShell 里，`F4` 或 `Alt+P` 在当前终端光标附近打开智能补全候选框；`Ctrl+Space` 只在没有被输入法占用时可用。
- SSH 标签页里，托盘全局热键 `Ctrl+Alt+P` 会直接读取本机 Windows Terminal 当前可见输入并弹出本机补全框，不需要服务器脚本或反向端口。
- 候选框会先显示本地快速建议，`git`、`ssh`、`docker`、`npm`、`python`、`java`、`adb` 这类命令不用先等 API。
- Kubernetes 常用命令也有本地候选，支持 `kube` 和 `kubectl`，例如 `kube get svc` 会直接给出 `-A`、`-n <命名空间>`、`-o wide`、`-o yaml` 等候选。
- AI 候选会在后台补充进列表；AI 会返回多条候选命令，不要求所有命令都预存在本地。
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

推荐一键安装全部本地入口：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\install-all.ps1
```

它会依次安装/检查：

- PowerShell 快捷键 profile
- 托盘常驻程序启动项
- VS Code 右键扩展
- 本地脚本语法和面板 smoke test

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
| `F4` | 推荐：打开智能补全候选框 |
| `Alt+P` | 本地 PowerShell 备用：打开智能补全候选框 |
| `Ctrl+Alt+P` | SSH 标签页推荐：托盘读取当前可见输入，在本机补全并写回 |
| `Ctrl+Alt+E` | SSH 标签页推荐：托盘读取当前可见输入，在本机解释 |
| `Ctrl+Space` | 可选：未被输入法占用时打开智能补全候选框 |
| `Ctrl+Shift+Space` | 备用：当 `Ctrl+Space` 被输入法或终端抢占时使用 |
| `Alt+C` | 复制 AI 补全 |
| `Alt+F` | 诊断选中文本或当前命令 |
| `F2` | 备用：解释当前命令 |
| `F3` | 备用：打开管理面板 |
| `F8` | 备用：诊断当前命令 |

如果某个组合键没有反应，先运行：

```powershell
taih-keys
taih-what-key
```

`taih-what-key` 会让 PSReadLine 显示终端实际收到的按键名。Windows Terminal、中文输入法、远端 SSH 会话都可能抢占 `Ctrl+Space`。你的机器上 `Ctrl+Space` 是中英文输入法切换，所以本地 PowerShell 优先用 `F4` 或 `Alt+P`；SSH 标签页优先用托盘全局热键 `Ctrl+Alt+P` 和 `Ctrl+Alt+E`。

## 常用命令

```powershell
taih-current                  # 解释当前命令
taih-panel                    # 打开或更新右侧管理面板
taih-ssh-panel                # 打开本地 SSH 远端控制面板，默认 root@us-vpn
taih-popup                    # 使用当前命令打开管理面板
taih-complete-popup           # 手动打开可编辑补全候选框
taih-complete-stable          # 不弹窗，直接请求 AI 并插入补全
taih-clip                     # 解释剪贴板内容
taih-clip -Mode fix -Window   # 在面板里诊断剪贴板里的报错
taih-panel-reset              # 清理卡住的面板状态
```

## 桌面入口

| 入口 | 适合场景 | 使用方式 |
| --- | --- | --- |
| PowerShell 快捷键 | 本地命令行补全、解释、诊断 | 加载 `powershell\taih-profile.ps1` 后使用 `Alt+/`、`F4`，`Ctrl+Space` 只作为可选键 |
| 右侧管理面板 | 持续查看解释、历史、配置、规则 | `taih-panel` 或 `Alt+?` |
| SSH 远端控制面板 | 像本地控制台一样操作远端服务器 | `taih-ssh-panel` |
| 托盘当前终端输入 | Windows Terminal、SSH 标签页当前正在输入的命令 | 启动 `powershell\tray.ps1`，在 SSH 标签页里按 `Ctrl+Alt+P` 补全，按 `Ctrl+Alt+E` 解释 |
| 托盘全局选区 | Windows Terminal、SSH、任意窗口选中文本 | 启动 `powershell\tray.ps1`，选中文本后按 `Ctrl+Alt+/` |
| VS Code 右键 | 解释代码块、命令片段、日志片段 | 安装扩展后，选中文本右键使用“终端 AI 助手” |
| SSH 反向隧道 | 高级备用：只有本机无法读取终端可见文本时才考虑 | 不作为日常推荐路径 |

Windows Terminal 没有稳定的第三方右键菜单扩展接口，所以项目提供托盘全局热键和 actions 配置说明，见：

```powershell
E:\3.13-aliyun-codex\5.2\terminal-ai-helper\integrations\windows-terminal\README.md
```

CLI 示例：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js explain --style brief -- "git status"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js complete --json -- "ssh"
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js tools --style brief --tools linux,k8s
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache clear
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache stats
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js config get
```

## 补全候选框

在命令行输入一部分命令，例如：

```powershell
ssh
```

按 `F4` 后会出现候选框；如果你的输入法没有占用 `Ctrl+Space`，也可以用 `Ctrl+Space`：

- 上方列表显示候选命令。
- 下方输入框可以直接修改当前候选。
- `方向提示` 可以写模糊目标，例如“偏网络排查”“偏 k8s service”“偏 Linux CPU 信息”，然后点 `刷新AI`。
- `刷新AI` 会跳过旧缓存重新请求 AI，并把新结果写回缓存；这样不会被旧缓存一直锁住。
- `Enter` 插回当前命令行。
- `解释` 按钮、`Ctrl+E` 或 `F1` 可以把当前候选命令送到右侧面板解释。
- `Esc` 关闭；点击回终端时，补全下拉框也会自动关闭并释放终端输入。
- `复制` 只复制候选，不修改当前命令行。

本地候选立即显示，AI 候选后台补充。重复相同补全时会命中缓存。

如果只看到 `--help` 一类候选，通常表示这条命令还没有本地规则，程序会先给通用兜底候选，同时等待 AI 后台补充。

如果 AI 候选没有追加，常见原因是 API 失败、模型返回格式不合法、或网络超时。状态栏会显示失败原因；本地候选仍然可以先用。

## 模型和配置

打开右侧面板：

```powershell
taih-panel
```

点击底部 `配置` 按钮，可以修改：

- 接口地址：`TAIH_BASE_URL`
- 模型：`TAIH_MODEL`
- 超时时间：`TAIH_TIMEOUT_MS`
- 默认工具集：`TAIH_TOOLS`
- 查看缓存统计
- 清理缓存

也可以用命令修改模型：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js config set model gpt-5.5
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js config set base-url https://qyapi.cjyyswq.com
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js config set timeout 30000
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js config set tools linux,k8s,ssh
```

如果已经打开多个 PowerShell，会话内环境变量可能还是旧值。重新加载 profile 或重开终端最稳。

## 占用和缓存

这个项目不会把大量内容放进内存长期占用。常驻的主要是当前 PowerShell 会话里的快捷键函数，以及你打开的面板窗口。

本地数据保存在：

```powershell
%USERPROFILE%\.terminal-ai-helper
```

默认限制：

- 历史记录最多保留最近 300 条。
- 缓存最多保留 500 个文件。
- 缓存总大小最多约 50 MB。
- 缓存默认 7 天过期。

查看占用：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache stats
```

清理缓存：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js cache clear
```

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
| `tools（工具菜单）` | 按工具集生成常用基础命令菜单 |

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

这里要分清两个概念：

- 本机 Windows Terminal 能看到 SSH 标签页里显示的文字，也能复制你用鼠标选中的内容。
- 远端服务器里的 bash/readline 不能读取 Windows Terminal 的鼠标选区，因为选区属于本机终端 UI。

### 方式一：本机直接读取 SSH 标签页当前输入（推荐）

这个方式不要求服务器安装任何东西，也不需要 `ssh -R`。它走本机 Windows UI Automation，从 Windows Terminal 当前标签页的可见文本里提取最后一行命令。

启动托盘：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

在 SSH 标签页里输入命令前缀，例如：

```bash
kube get svc
```

然后使用：

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Alt+P` | 读取当前终端输入，弹出本机补全候选框，选择后写回当前 SSH 命令行 |
| `Ctrl+Alt+E` | 读取当前终端输入，打开本机管理面板解释 |
| `Ctrl+Alt+/` | 解释鼠标选中的终端文本 |
| `Ctrl+Alt+F` | 诊断鼠标选中的终端文本 |

如果某个终端版本没有向 Windows 暴露可访问文本，`Ctrl+Alt+P/E` 可能读不到当前输入；这时优先退回到鼠标选中文本的 `Ctrl+Alt+/` 或 `Ctrl+Alt+F`。日常使用不要先去服务器加载脚本。

### 方式二：本地 SSH 远端控制面板

如果你想“在自己桌面窗口里像本地控制面板一样操作远端”，优先用这个入口：

```powershell
taih-ssh-panel
```

默认连接 `root@us-vpn`。也可以指定目标：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\ssh-panel.ps1 -Target root@43.112.115.205
```

面板布局：

- 左上：SSH 目标、远端 shell、工具集。
- 左中：远端终端输出区。
- 左下：命令输入和常用功能按钮，例如执行远端、测试连接、解释命令、AI 补全、诊断输出、工具菜单、Linux 排查、K8s 服务。
- 右侧：AI 输出和任务记录。

这个方式不需要在服务器安装 terminal-ai-helper。它是在本机通过 `ssh <目标> -- bash -lc <命令>` 执行远端命令，API key 仍然留在本机。

测试命令：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\apps\powershell\ssh-panel.ps1 -SmokeTest -Target root@us-vpn
```

### 方式三：分析已显示的 SSH 文本

所以，如果只是想分析你桌面上已经看到的远端命令、报错或日志，推荐使用本机托盘的全局选区热键，不需要在服务器安装任何东西：

```powershell
powershell -ExecutionPolicy Bypass -File E:\3.13-aliyun-codex\5.2\terminal-ai-helper\powershell\tray.ps1
```

用法：

- 在 Windows Terminal 的 SSH 标签页里，用鼠标选中一段远端命令、报错或日志。
- 按 `Ctrl+Alt+/`：复制选中文本并打开本机解释面板。
- 按 `Ctrl+Alt+F`：复制选中文本并打开本机诊断面板。

这个方式读取的是本机 Windows Terminal 选区/剪贴板，API key 仍然留在本机。也就是说，你在 SSH 里敲命令、看到输出，本机助手可以通过“选中并复制”分析这些文本。

注意：如果没有选中文本，`Ctrl+C` 在终端里可能会被远端 shell 当作中断，所以使用前请先选中文本。

### 方式四：远端 bash 快捷键（高级备用，不推荐日常使用）

这不是 SSH 标签页的主方案。只有在本机 UI Automation 读不到当前输入，并且你明确需要远端 bash/readline 级别的当前行时，才考虑这个方案。正常情况下，直接用本机托盘 `Ctrl+Alt+P`/`Ctrl+Alt+E` 读取 Windows Terminal 当前可见文本即可。

高级备用方案会让远端 readline 把当前命令通过反向隧道发回本机：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888 --replace
ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>
```

远端加载 bash 集成：

```bash
source /path/to/terminal-ai-helper/integrations/ssh/taih-bash.sh
```

远端 `F4` 或 `Alt+P` 的补全流程现在和本地更接近；`Ctrl+Space` 只在没有被输入法抢占时可用：

- 远端 bash/readline 读取你正在编辑的当前命令行。
- 当前命令通过 SSH 反向隧道发回本机 `http://127.0.0.1:17888/complete-popup`。
- 本机弹出可编辑的智能补全候选框，你可以用鼠标选择、修改、复制或解释候选。
- 选择后，候选命令会返回远端 bash，并替换当前命令行。

如果本机弹窗不可用，会自动退回到原来的纯文本 AI 补全。更新项目后如果 `node ... serve --port 17888` 提示端口已经被占用，请用 `--replace` 替换旧 helper server，否则 SSH 可能仍连到旧代码：

```powershell
node E:\3.13-aliyun-codex\5.2\terminal-ai-helper\bin\taih.js serve --port 17888 --replace
```

远端也可以手动把文本发回本机面板或补全弹窗：

```bash
taih explain 'systemctl status <服务名>'
journalctl -u <服务名> -n 80 --no-pager | taih fix
taih complete 'kubectl get svc'
taih-complete-popup 'kubectl get svc'
taih-panel explain 'systemctl status <服务名>'
journalctl -u <服务名> -n 80 --no-pager | taih-panel fix
taih-tools
taih-tools linux k8s docker
taih-panel tools
```

## 测试

```powershell
npm run check
npm test
```

`npm test` 会检查：

- Node.js 入口和模块语法。
- VS Code 扩展入口语法。
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
