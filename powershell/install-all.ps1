param(
    [switch]$SkipApiKey,
    [switch]$NoTrayStartup,
    [switch]$NoVsCode
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

Step "检查 Node.js 和项目脚本"
node (Join-Path $root "bin\taih.js") doctor

if (-not $SkipApiKey) {
    Step "配置用户环境变量"
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "powershell\install-user-env.ps1")
}

Step "安装 PowerShell 快捷键 profile"
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "powershell\install-profile.ps1")

if (-not $NoTrayStartup) {
    Step "安装托盘常驻入口"
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "powershell\install-tray-startup.ps1")
}

if (-not $NoVsCode) {
    Step "安装 VS Code 右键扩展"
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "powershell\install-vscode-extension.ps1")
}

Step "运行本地检查"
Push-Location $root
try {
    npm run check
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "powershell\test-panel.ps1") -SkipApi
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "安装完成。请重启 PowerShell / VS Code 后使用：" -ForegroundColor Green
Write-Host "  PowerShell: Alt+/、Alt+?、Ctrl+Space、F4"
Write-Host "  托盘全局选区: Ctrl+Alt+/ 解释，Ctrl+Alt+F 诊断"
Write-Host "  VS Code: 选中文本后右键使用“终端 AI 助手”"
