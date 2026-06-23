param(
    [switch]$SkipApiKey,
    [switch]$NoTrayStartup,
    [switch]$UseLegacyPowerShellTray,
    [switch]$NoVsCode
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$warnings = New-Object System.Collections.Generic.List[string]

function L {
    param([string]$Text)
    $evaluator = {
        param($Match)
        [string][char]([Convert]::ToInt32($Match.Groups[1].Value, 16))
    }
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

function Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Has-ApiKey {
    $processValue = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
    if ($processValue) { return $true }
    $userValue = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "User")
    if ($userValue) { return $true }
    return $false
}

function Invoke-Checked {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

Step (L '\u68c0\u67e5 Node.js \u548c\u9879\u76ee\u811a\u672c')
Invoke-Checked -FilePath "node" -Arguments @((Join-Path $root "bin\taih.js"), "doctor")

if ($SkipApiKey) {
    Step (L '\u8df3\u8fc7 API key \u914d\u7f6e')
} elseif (Has-ApiKey) {
    Step (L '\u5df2\u68c0\u6d4b\u5230 API key\uff0c\u8df3\u8fc7\u91cd\u590d\u8f93\u5165')
} else {
    Step (L '\u914d\u7f6e\u7528\u6237\u73af\u5883\u53d8\u91cf')
    Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts\install\user-env.ps1"))
}

Step (L '\u5b89\u88c5 PowerShell \u5feb\u6377\u952e profile')
try {
    Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts\install\profile.ps1"))
} catch {
    $warnings.Add((L 'PowerShell profile \u81ea\u52a8\u5199\u5165\u5931\u8d25\uff0c\u4f46\u53ef\u4ee5\u7ee7\u7eed\u4f7f\u7528 terminal-ai-helper.cmd \u6216\u624b\u52a8\u70b9\u52a0\u8f7d profile\u3002')) | Out-Null
}

if (-not $NoTrayStartup) {
    if ($UseLegacyPowerShellTray) {
        Step (L '\u5b89\u88c5 PowerShell \u6258\u76d8\u5e38\u9a7b\u5165\u53e3')
        Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts\install\tray-startup.ps1"))
    } else {
        Step "安装 TerminalAi.Desktop 桌面常驻入口"
        Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts\install\desktop-startup.ps1"), "-Build")
    }
}

if (-not $NoVsCode) {
    Step (L '\u5b89\u88c5 VS Code \u53f3\u952e\u6269\u5c55')
    Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "scripts\install\vscode-extension.ps1"))
}

Step (L '\u8fd0\u884c\u672c\u5730\u68c0\u67e5')
Push-Location $root
try {
    Invoke-Checked -FilePath "npm" -Arguments @("run", "check")
    Invoke-Checked -FilePath "powershell" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tests\powershell\panel.ps1"), "-SkipApi")
} finally {
    Pop-Location
}

Write-Host ""
Write-Host (L '\u5b89\u88c5\u5b8c\u6210\u3002\u8bf7\u91cd\u542f PowerShell / VS Code \u540e\u4f7f\u7528\uff1a') -ForegroundColor Green
Write-Host (L '  PowerShell: Alt+/\u3001Alt+?\u3001Ctrl+Space\u3001F4')
Write-Host "  TerminalAi.Desktop: Ctrl+Alt+P 补全当前终端输入，Ctrl+Alt+E 解释当前终端输入"
Write-Host (L '  \u6258\u76d8\u5168\u5c40\u9009\u533a: Ctrl+Alt+/ \u89e3\u91ca\uff0cCtrl+Alt+F \u8bca\u65ad')
Write-Host (L '  VS Code: \u9009\u4e2d\u6587\u672c\u540e\u53f3\u952e\u4f7f\u7528\u201c\u7ec8\u7aef AI \u52a9\u624b\u201d')
if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host (L '\u6ce8\u610f\uff1a') -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
    Write-Host (L '  \u624b\u52a8\u52a0\u8f7d\u547d\u4ee4\uff1a') -ForegroundColor Yellow
    Write-Host "    . `"$root\apps\powershell\profile.ps1`"" -ForegroundColor Yellow
}
